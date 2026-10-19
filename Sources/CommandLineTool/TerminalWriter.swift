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


    /// Takes no more output. A thread that waits in `enqueue` returns.
    func close() {
        condition.lock()
        isClosed = true
        queuedOutput = []
        condition.broadcast()
        condition.unlock()
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
