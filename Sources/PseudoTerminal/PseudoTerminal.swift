import Darwin
import Dispatch

/// A program running on a new pseudo terminal.
///
/// The program is a session leader, and the pseudo terminal is its controlling
/// terminal, so a shell can run jobs and the kernel sends hang-up and resize
/// signals the way a real terminal would.
///
/// All methods can be called from any thread. The object closes its
/// descriptor once, when the program has ended and all output has been read.
public final class PseudoTerminal: @unchecked Sendable {
    /// The process identifier of the program. It is also the identifier of the
    /// program's process group and of its terminal session.
    public let processIdentifier: pid_t

    /// The device path of the terminal, such as `/dev/ttys004`. Other programs
    /// can open it to read the terminal's settings.
    public let terminalPath: String

    /// The bytes the program writes, in order. The stream finishes after the
    /// last byte of a program that has ended, and before `waitForExit` returns.
    /// Only one task may read it.
    public let output: AsyncStream<[UInt8]>

    private static let readChunkSize = 64 * 1024
    /// The status reported when `waitpid` fails and the real status is
    /// unknown. A shell's `wait` reports 127 for a process whose status it
    /// does not know. A clean 0 would claim a success that nobody saw.
    static let unknownExitStatus: Int32 = 127

    private let queue = DispatchQueue(label: "PseudoTerminal")
    private let outputContinuation: AsyncStream<[UInt8]>.Continuation

    // Everything below belongs to `queue`. No other thread touches it.
    private var master: Int32
    private var readSource: DispatchSourceRead?
    private var exitSource: DispatchSourceProcess?
    private var sourcesStillUsingMaster = 1
    private var exit: ProgramExit?
    private var exitWaiters: [CheckedContinuation<ProgramExit, Never>] = []

    /// Starts the program.
    public init(launching launch: ProgramLaunch) throws {
        let started = try launch.start()
        master = started.masterDescriptor
        processIdentifier = started.processIdentifier
        terminalPath = started.terminalPath
        (output, outputContinuation) = AsyncStream.makeStream(of: [UInt8].self)
        startWatching()
    }


    /// Waits for the program to end and returns how.
    public func waitForExit() async -> ProgramExit {
        await withCheckedContinuation { continuation in
            queue.async {
                if let exit = self.exit {
                    continuation.resume(returning: exit)
                } else {
                    self.exitWaiters.append(continuation)
                }
            }
        }
    }

    // MARK: - Starting


    private func startWatching() {
        let reader = DispatchSource.makeReadSource(fileDescriptor: master, queue: queue)
        reader.setEventHandler { [self] in readAvailableOutput() }
        reader.setCancelHandler { [self] in releaseMaster() }
        readSource = reader

        let watcher = DispatchSource.makeProcessSource(identifier: processIdentifier, eventMask: .exit, queue: queue)
        watcher.setEventHandler { [self] in reapIfExited(retryingWhileExiting: true) }
        exitSource = watcher

        reader.resume()
        watcher.resume()
        // The program may have ended before the watcher existed.
        queue.async { self.reapIfExited() }
    }

    // MARK: - Output (on the queue)

    private func readAvailableOutput(honoringBackpressure: Bool = true) {
        guard master >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: Self.readChunkSize)
        while true {
            let count = read(master, &buffer, buffer.count)
            if count > 0 {
                outputContinuation.yield(Array(buffer[0..<count]))
                continue
            }
            if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) {
                // Every holder of the terminal closed it. The source would
                // fire forever, so stop it. The exit watcher finishes the job.
                readSource?.cancel()
            }
            if count < 0 && errno == EINTR { continue }
            return
        }
    }

    // MARK: - Exit (on the queue)

    private func reapIfExited(retryingWhileExiting: Bool = false) {
        guard exit == nil else { return }
        var status: Int32 = 0
        var result: pid_t
        repeat {
            result = waitpid(processIdentifier, &status, WNOHANG)
        } while result < 0 && errno == EINTR
        guard result != 0 else {
            // The system reports the exit before the program counts as ended.
            // A session leader with a controlling terminal takes longer, because
            // the kernel hangs up the terminal first. The event comes only once,
            // so ask again until the program can be reaped.
            if retryingWhileExiting {
                queue.asyncAfter(deadline: .now() + .milliseconds(5)) { [self] in
                    reapIfExited(retryingWhileExiting: true)
                }
            }
            return
        }
        // On another waitpid error, such as ECHILD after another waiter reaped
        // the child, the status is lost and no later call can learn it. Report
        // an unknown status instead of waiting forever.
        let reason = result < 0 ? ProgramExit.exited(status: Self.unknownExitStatus) : ProgramExit(waitStatus: status)

        // Output the program wrote before it ended can still sit in the
        // kernel buffer. Deliver it before the stream finishes.
        readAvailableOutput(honoringBackpressure: false)
        outputContinuation.finish()
        exit = reason

        exitSource?.cancel()
        exitSource = nil
        readSource?.cancel()
        for waiter in exitWaiters {
            waiter.resume(returning: reason)
        }
        exitWaiters.removeAll()
    }

    // The descriptor closes when the last source that watched it is gone,
    // because closing it earlier would break a source that still runs.
    private func releaseMaster() {
        sourcesStillUsingMaster -= 1
        guard sourcesStillUsingMaster == 0, master >= 0 else { return }
        close(master)
        master = -1
        readSource = nil
    }
}
