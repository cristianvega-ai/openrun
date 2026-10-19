import Darwin
import Foundation
import PseudoTerminal
import TerminalEmulation

public final class AttachedTerminal: @unchecked Sendable {
    private let pseudoTerminal: PseudoTerminal
    private let screen: Terminal
    private let lock = NSLock()
    private let replies = ReplyCounter()
    /// Every byte the program wrote, in order. Guarded by `lock`.
    private var received: [UInt8] = []
    /// Typed keys, in order. One task writes them, so they reach the program
    /// in the order they were typed, also when a write waits for room.
    private let typing: AsyncStream<[UInt8]>.Continuation

    /// Runs a shell script in the pseudo terminal. The script usually starts
    /// `openrun attach` and prints what happens around it.
    public init(shellScript: String, columns: UInt16 = 80, rows: UInt16 = 24, folder: URL) throws {
        screen = try Terminal(size: TerminalSize(columns: columns, rows: rows), scrollbackLimit: 1000)
        let launch = ProgramLaunch(
            executablePath: "/bin/sh",
            argumentZero: "sh",
            arguments: ["-c", shellScript],
            folder: folder.path,
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "xterm-256color", "HOME": folder.path],
            size: PseudoTerminalSize(columns: columns, rows: rows)
        )
        let pseudoTerminal = try PseudoTerminal(launching: launch)
        self.pseudoTerminal = pseudoTerminal
        let (keys, typing) = AsyncStream.makeStream(of: [UInt8].self)
        self.typing = typing
        // The screen keeps its reply handler, so the handler must not hold
        // this object: that would be a cycle, and the screen's memory would
        // never be freed. The counter and the pseudo terminal are enough.
        let replies = replies
        try screen.setReplyHandler { bytes in
            replies.increment()
            pseudoTerminal.write(bytes)
        }
        Task {
            for await chunk in keys {
                try? await pseudoTerminal.type(chunk)
            }
        }
        // The task holds this object only while it handles a chunk. A test
        // that lets go of the terminal frees it, also while the program runs.
        Task { [weak self] in
            for await chunk in pseudoTerminal.output {
                guard let self else { return }
                lock.withLock {
                    received += chunk
                    screen.write(chunk)
                }
            }
        }
    }

    /// The process identifier of the script's shell.
    public var processIdentifier: pid_t { pseudoTerminal.processIdentifier }

    /// How many answers this terminal has sent to its program.
    public var repliesSent: Int {
        replies.count
    }

    /// The text on the screen now.
    public var screenText: String {
        lock.withLock { String(decoding: (try? screen.formatted(.plainText)) ?? [], as: UTF8.self) }
    }

    /// Waits until the screen shows the text.
    public func waitForScreen(containing text: String, timeout: Duration = .seconds(15)) async -> Bool {
        await eventually(timeout: timeout) { screenText.contains(text) }
    }

    /// Ends the script and everything it started, at once. A test calls it
    /// when it ends, so that no process outlives the test run.
    public func closeNow() {
        killpg(processIdentifier, SIGKILL)
    }

    private final class ReplyCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = 0
        var count: Int { lock.withLock { stored } }
        func increment() { lock.withLock { stored += 1 } }
    }
}
