import Darwin
import Foundation

final class TerminalWriter: @unchecked Sendable {
    /// How attaching ends: the exit code of the tool and its last message.
    struct Ending: Equatable, Sendable {
        var exitCode: Int32
        /// An ending by a signal prints none.
        var message: String? = nil
    }

    /// What the main thread does next.
    enum Request: Equatable {
        case write([UInt8])
        case end(Ending)
    }

    enum WriteResult: Equatable {
        case written
        /// A request to end or to suspend came first.
        case interrupted(writtenCount: Int)
        case timedOut(writtenCount: Int)
        case failed(writtenCount: Int, reason: String)

        var writtenCount: Int? {
            switch self {
            case .written: nil
            case .interrupted(let count), .timedOut(let count), .failed(let count, _): count
            }
        }
    }

    /// The output that may wait for the terminal. The thread that receives
    /// it then waits too, the socket fills up, and the session process
    /// treats this client as slow.
    static let queuedOutputLimit = 1 << 20

    /// How long the closing sequences and the last message may wait for a
    /// terminal that takes no output.
    static let closingTimeLimit: Duration = .seconds(1)

    private let descriptor: Int32
    /// The flags of standard output to put back, when the writer could not
    /// open the terminal again and had to make standard output nonblocking.
    private let originalFlags: Int32?
    /// A pipe that wakes the main thread from `poll`.
    private let wakeReading: Int32
    private let wakeWriting: Int32

    // Guarded by `condition`, which also wakes the receiving thread when
    // the output queue has room again.
    private let condition = NSCondition()
    private var urgentEnding: Ending?
    private var endingAfterOutput: Ending?
    private var wantsSuspension = false
    private var queuedOutput: [UInt8] = []
    private var isClosed = false
    private var hasStoppedWriting = false

    /// Opens the terminal of standard output for writes that do not block.
    init() throws {
        var pipeEnds: [Int32] = [0, 0]
        guard pipe(&pipeEnds) == 0 else {
            throw CommandLineToolError.failure("attach cannot make a pipe: \(String(cString: strerror(errno))).")
        }
        for end in pipeEnds {
            _ = fcntl(end, F_SETFL, fcntl(end, F_GETFL) | O_NONBLOCK)
            _ = fcntl(end, F_SETFD, FD_CLOEXEC)
        }
        (wakeReading, wakeWriting) = (pipeEnds[0], pipeEnds[1])

        // A descriptor of its own keeps O_NONBLOCK away from standard input,
        // standard output and the shell, which share theirs.
        var name = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let reopened = ttyname_r(STDOUT_FILENO, &name, name.count) == 0
            ? open(name, O_WRONLY | O_NONBLOCK | O_NOCTTY | O_CLOEXEC)
            : -1
        if reopened >= 0 {
            descriptor = reopened
            originalFlags = nil
        } else {
            // Another user's terminal cannot be opened by its path. Then
            // standard output itself stops blocking until the writer is done.
            descriptor = dup(STDOUT_FILENO)
            let flags = fcntl(STDOUT_FILENO, F_GETFL)
            originalFlags = flags
            _ = fcntl(STDOUT_FILENO, F_SETFL, flags | O_NONBLOCK)
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        }
    }

    deinit {
        stopWriting()
        Darwin.close(wakeReading)
        Darwin.close(wakeWriting)
    }

    // MARK: - Requests from any thread

    /// Queues output for the terminal. Waits while the queue is full.
    /// Returns `false` once the writer takes no more output.
    func enqueue(output bytes: [UInt8]) -> Bool {
        condition.lock()
        while !isClosed && queuedOutput.count >= Self.queuedOutputLimit {
            condition.wait()
        }
        let accepted = !isClosed
        if accepted { queuedOutput += bytes }
        condition.unlock()
        wake()
        return accepted
    }

    /// Asks the writer to end attaching. With `afterOutput`, the queued
    /// output is written first, so the last words of a program that ends
    /// reach the terminal. Without it, the ending is urgent: the queued
    /// output is dropped. Among urgent endings, such as a detach or a signal,
    /// the first one decides. Among endings after output, such as the exit of
    /// the program or a lost connection, the first one decides. An urgent
    /// ending beats an ending after output, also when the other came first.
    func requestEnd(_ ending: Ending, afterOutput: Bool) {
        condition.lock()
        if afterOutput {
            if endingAfterOutput == nil { endingAfterOutput = ending }
        } else if urgentEnding == nil {
            urgentEnding = ending
        }
        condition.unlock()
        wake()
    }

    /// Asks the writer to suspend attaching, or to go on after a suspension.
    /// A continue that comes before the writer handled the suspension cancels it.
    func requestSuspension(_ suspended: Bool) {
        condition.lock()
        wantsSuspension = suspended
        condition.unlock()
        wake()
    }

    /// A request to end that came before the terminal changed. Attaching
    /// then ends without touching the terminal.
    var endingBeforeStart: Ending? {
        condition.withLock { urgentEnding }
    }


    /// Takes no more output. A thread that waits in `enqueue` returns.
    func close() {
        condition.lock()
        isClosed = true
        queuedOutput = []
        condition.broadcast()
        condition.unlock()
    }

    // MARK: - The main thread

    /// The next request. A request to end that is not after the output comes
    /// first, then a change of suspension. Output and the ending after it
    /// come only when the main thread has nothing left to write and is not
    /// suspended. Without `waiting`, returns `nil` when nothing is there.
    func nextRequest(isSuspended: Bool, waiting: Bool) -> Request? {
        while true {
            condition.lock()
            let request: Request? = if let urgentEnding {
                .end(urgentEnding)
            } else if waiting && !isSuspended && !queuedOutput.isEmpty {
                .write(queuedOutput)
            } else if waiting && !isSuspended, let endingAfterOutput {
                .end(endingAfterOutput)
            } else {
                nil
            }
            if case .write = request {
                queuedOutput = []
                condition.broadcast()
            }
            condition.unlock()
            if request != nil || !waiting { return request }
            waitForWake(alsoForRoom: false)
        }
    }

    /// Writes all bytes, unless a request to end or to suspend comes first
    /// (with `stoppingForRequests`), the deadline passes, or the terminal
    /// fails.
    func write(_ bytes: [UInt8], until deadline: ContinuousClock.Instant? = nil, stoppingForRequests: Bool = true) -> WriteResult {
        var offset = 0
        while offset < bytes.count {
            if stoppingForRequests && hasUrgentRequest {
                return .interrupted(writtenCount: offset)
            }
            let count = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress! + offset, bytes.count - offset) }
            if count > 0 {
                offset += count
                continue
            }
            if count < 0 && errno == EINTR { continue }
            guard count < 0 && errno == EAGAIN else {
                return .failed(writtenCount: offset, reason: String(cString: strerror(count < 0 ? errno : EIO)))
            }
            var timeout: Int32 = -1
            if let deadline {
                let remaining = deadline - .now
                guard remaining > .zero else { return .timedOut(writtenCount: offset) }
                timeout = Self.milliseconds(roundingUp: remaining)
            }
            waitForWake(alsoForRoom: true, timeout: timeout)
        }
        return .written
    }

    /// Whether the terminal takes output now. A terminal that does not has
    /// a full output queue: the window reads nothing, as a frozen `ssh` does.
    var takesOutputNow: Bool {
        var descriptors = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        return poll(&descriptors, 1, 0) > 0 && descriptors.revents & Int16(POLLOUT) != 0
    }

    /// Writes the sequences that undo what the program switched on, and puts
    /// the original mode back. When the terminal takes no output, the mode
    /// comes back first, because the sequences may never reach it. Neither
    /// waits longer than `closingTimeLimit`, and no request stops them.
    /// Returns how many bytes of the sequences reached the terminal.
    func writeClosing(_ closingSequences: [UInt8], restoring mode: RawTerminalMode) -> Int {
        let deadline = ContinuousClock.now + Self.closingTimeLimit
        let result: WriteResult
        if takesOutputNow {
            result = write(closingSequences, until: deadline, stoppingForRequests: false)
            mode.restore()
        } else {
            mode.restore(waitingForOutputAtMost: .zero)
            result = write(closingSequences, until: deadline, stoppingForRequests: false)
        }
        return result.writtenCount ?? closingSequences.count
    }

    /// Writes the last message to standard error, after `stopWriting`. It
    /// waits at most `closingTimeLimit` for room. A pipe that nobody reads
    /// gives an error, not a SIGPIPE, because `AttachSignals` ignores it.
    static func writeLastMessage(_ message: String) {
        var descriptor = pollfd(fd: STDERR_FILENO, events: Int16(POLLOUT), revents: 0)
        guard poll(&descriptor, 1, milliseconds(roundingUp: closingTimeLimit)) > 0,
              descriptor.revents & Int16(POLLOUT) != 0 else { return }
        let bytes = Array(message.utf8)
        _ = bytes.withUnsafeBytes { Darwin.write(STDERR_FILENO, $0.baseAddress, $0.count) }
    }

    /// Ends the writing: closes the second descriptor of the terminal, and
    /// puts back the flags of standard output when the writer changed them.
    /// Safe to call again.
    func stopWriting() {
        let isFirst = condition.withLock {
            defer { hasStoppedWriting = true }
            return !hasStoppedWriting
        }
        guard isFirst else { return }
        if let originalFlags { _ = fcntl(STDOUT_FILENO, F_SETFL, originalFlags) }
        Darwin.close(descriptor)
    }

    // MARK: - Waking

    private var hasUrgentRequest: Bool {
        condition.withLock { urgentEnding != nil }
    }

    private func wake() {
        var byte: UInt8 = 1
        // A full pipe already holds a wake.
        _ = Darwin.write(wakeWriting, &byte, 1)
    }

    /// Waits until another thread wakes the main thread, or with
    /// `alsoForRoom`, until the terminal takes output again.
    private func waitForWake(alsoForRoom: Bool, timeout: Int32 = -1) {
        var descriptors = [
            pollfd(fd: wakeReading, events: Int16(POLLIN), revents: 0),
            pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0),
        ]
        // An interrupted poll returns early, and the caller looks again.
        _ = poll(&descriptors, alsoForRoom ? 2 : 1, timeout)
        var drained = [UInt8](repeating: 0, count: 64)
        while Darwin.read(wakeReading, &drained, drained.count) > 0 {}
    }

    private static func milliseconds(roundingUp duration: Duration) -> Int32 {
        let components = duration.components
        let milliseconds = components.seconds * 1000 + (components.attoseconds + 999_999_999_999_999) / 1_000_000_000_000_000
        return Int32(clamping: milliseconds)
    }
}
