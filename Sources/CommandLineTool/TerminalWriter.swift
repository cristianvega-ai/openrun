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
}
