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

    let queue = DispatchQueue(label: "AgentProgram")

    // Everything below belongs to `queue`. No other thread touches it.
    var outputDescriptor: Int32
    var errorDescriptor: Int32
    var inputDescriptor: Int32
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
        reaper = ProcessGroupReaper(processIdentifier: processIdentifier, queue: queue) { [self] in programEnded($0) }
        reaper?.start()
    }
}
