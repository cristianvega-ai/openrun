import Darwin
import Dispatch
import PseudoTerminal

/// An agent program that runs on pipes, such as `claude -p`.
///
/// The program leads a new process group. Signals go to the whole group,
/// so a command or a server that the agent started does not stay behind,
/// and `ProcessGroupReaper` ends the rest of the group when the program
/// ends. When nobody holds the object any more, it ends the program and
/// its group at once with SIGKILL, so keep the object for as long as the
/// program must run.
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
    /// The most bytes of standard error that the object keeps: the newest.
    public static let standardErrorLimit = 64 * 1024

    let queue = DispatchQueue(label: "AgentProgram")
    let outputContinuation: AsyncStream<[UInt8]>.Continuation

    // Everything below belongs to `queue`. No other thread touches it.
    var outputDescriptor: Int32
    var errorDescriptor: Int32
    var inputDescriptor: Int32
    var outputSource: DispatchSourceRead?
    var outputSourceIsSuspended = false
    var unconsumedBytes = 0
    var errorSource: DispatchSourceRead?
    var standardError: [UInt8] = []
    var inputSource: DispatchSourceWrite?
    var inputSourceIsSuspended = true
    var pendingInput: [PendingInput] = []
    var inputIsClosing = false
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

    /// The handlers hold the object weakly, so that a program that nobody
    /// holds is not kept by its own sources. Each cancel handler closes the
    /// descriptor that it was made for, also after the object is gone.
    private func startWatching() {
        let output = outputDescriptor, error = errorDescriptor, input = inputDescriptor
        let reader = DispatchSource.makeReadSource(fileDescriptor: output, queue: queue)
        reader.setEventHandler { [weak self] in self?.readOutput() }
        reader.setCancelHandler { [weak self] in close(output); self?.outputDescriptor = -1 }
        outputSource = reader
        reader.resume()
        let errorReader = DispatchSource.makeReadSource(fileDescriptor: error, queue: queue)
        errorReader.setEventHandler { [weak self] in self?.readStandardError() }
        errorReader.setCancelHandler { [weak self] in close(error); self?.errorDescriptor = -1 }
        errorSource = errorReader
        errorReader.resume()
        let writer = DispatchSource.makeWriteSource(fileDescriptor: input, queue: queue)
        writer.setEventHandler { [weak self] in self?.pumpInput() }
        writer.setCancelHandler { [weak self] in close(input); self?.inputDescriptor = -1 }
        inputSource = writer
        reaper = ProcessGroupReaper(processIdentifier: processIdentifier, queue: queue) { [weak self] in self?.programEnded($0) }
        reaper?.start()
    }

    /// A program that nobody holds any more ends at once with its group, so
    /// a forgotten object cannot leave an agent behind. The reaper stays
    /// until its exit event and reaps the program. No block on the queue
    /// holds the object now, so the state can be read here.
    deinit {
        outputContinuation.finish()
        let reaper = reaper
        let sources: [any DispatchSourceProtocol] = [outputSource, errorSource, inputSource].compactMap { $0 }
        let suspended: [any DispatchSourceProtocol] = [outputSourceIsSuspended ? outputSource : nil, inputSourceIsSuspended ? inputSource : nil]
            .compactMap { $0 }
        queue.async {
            reaper?.signalGroup(SIGKILL)
            // A suspended source runs its cancel handler only after a resume.
            suspended.forEach { $0.resume() }
            sources.forEach { $0.cancel() }
        }
    }
}
