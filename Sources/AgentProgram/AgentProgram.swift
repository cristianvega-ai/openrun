import Darwin
import Dispatch
import PseudoTerminal

/// An agent program that runs on pipes, such as `claude -p`.
///
/// The program leads a new process group. Signals go to the whole group,
/// so a command or a server that the agent started does not stay behind,
/// and `ProcessGroupReaper` ends the rest of the group when the program
/// ends.
///
/// All methods can be called from any thread.
public final class AgentProgram: @unchecked Sendable {
    public let processIdentifier: pid_t

    /// The bytes that the program writes on its standard output, in order.
    /// The stream finishes after the program ended, and before
    /// `waitForExit` returns. Only one task may read it.
    ///
    /// Call `markOutputConsumed` for each chunk that has been dealt with.
    /// Reading stops while too many bytes wait, and the program then waits
    /// in its own write.
    public let output: AsyncStream<[UInt8]>

    static let readChunkSize = 64 * 1024
    /// Reading stops above the high mark and starts again below the low mark.
    static let unconsumedHighMark = 4 * 1024 * 1024
    static let unconsumedLowMark = 1 * 1024 * 1024

    let queue = DispatchQueue(label: "AgentProgram")
    let outputContinuation: AsyncStream<[UInt8]>.Continuation

    // Everything below belongs to `queue`. No other thread touches it.
    var outputDescriptor: Int32
    var errorDescriptor: Int32
    var inputDescriptor: Int32
    var outputSource: DispatchSourceRead?
    var outputSourceIsSuspended = false
    var unconsumedBytes = 0
    var reaper: ProcessGroupReaper?
    var exit: ProgramExit?
    var exitWaiters: [CheckedContinuation<ProgramExit, Never>] = []

    /// Starts the program.
    public init(launching launch: AgentProgramLaunch) throws {
        let started = try PipeSpawn.start(launch)
        processIdentifier = started.processIdentifier
        inputDescriptor = started.inputDescriptor
        outputDescriptor = started.outputDescriptor
        errorDescriptor = started.errorDescriptor
        (output, outputContinuation) = AsyncStream.makeStream(of: [UInt8].self)
        queue.async { self.startWatching() }
    }

    /// Waits for the program to end and returns how.
    public func waitForExit() async -> ProgramExit {
        await withCheckedContinuation { continuation in
            queue.async {
                if let exit = self.exit { continuation.resume(returning: exit) } else { self.exitWaiters.append(continuation) }
            }
        }
    }

    private func startWatching() {
        let reader = DispatchSource.makeReadSource(fileDescriptor: outputDescriptor, queue: queue)
        reader.setEventHandler { [self] in readOutput() }
        reader.setCancelHandler { [self] in close(outputDescriptor); outputDescriptor = -1 }
        outputSource = reader
        reader.resume()
        reaper = ProcessGroupReaper(processIdentifier: processIdentifier, queue: queue) { [self] in programEnded($0) }
        reaper?.start()
    }
}
