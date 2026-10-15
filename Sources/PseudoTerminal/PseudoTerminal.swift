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
}
