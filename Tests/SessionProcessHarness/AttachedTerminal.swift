import Darwin
import Foundation
import PseudoTerminal
import TerminalEmulation

/// A program that runs in a pseudo terminal that the test controls, with a
/// terminal screen that shows what the program drew. It plays the part of the
/// user's terminal window for `openrun attach`.
///
/// Like a real terminal window, it answers the queries that the output
/// contains, such as the device attributes query. It counts its answers, so a
/// test can tell who answered.
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

    /// The visible screen as the sequences that draw it, with colors and
    /// styles. A test reads the style of text from it.
    public var screenWithStyles: String {
        lock.withLock { String(decoding: (try? screen.formatted(.virtualTerminalSequences)) ?? [], as: UTF8.self) }
    }

    /// Whether the terminal shows its alternate screen now.
    public var isAlternateScreenActive: Bool {
        lock.withLock { screen.isAlternateScreenActive }
    }

    /// Every byte that the program wrote to this terminal so far, in order.
    /// A test reads what `openrun attach` sent around an event from it.
    public var receivedBytes: [UInt8] {
        lock.withLock { received }
    }

    /// Types text, as keys.
    public func type(_ text: String) {
        typing.yield(Array(text.utf8))
    }

    /// Types raw bytes, such as the detach key.
    public func type(bytes: [UInt8]) {
        typing.yield(bytes)
    }

    /// Waits until the screen shows the text.
    public func waitForScreen(containing text: String, timeout: Duration = .seconds(15)) async -> Bool {
        await eventually(timeout: timeout) { screenText.contains(text) }
    }

    /// Changes the size of the window, as dragging a window corner does.
    public func resize(columns: UInt16, rows: UInt16) throws {
        try lock.withLock { try screen.resize(to: TerminalSize(columns: columns, rows: rows)) }
        try pseudoTerminal.resize(to: PseudoTerminalSize(columns: columns, rows: rows))
    }

    /// Whether the terminal is in raw mode: no line editing and no echo.
    public var isInRawMode: Bool {
        // Opening the terminal by its path shows the settings that the
        // program under test made. O_NOCTTY keeps the test from adopting it.
        let descriptor = open(pseudoTerminal.terminalPath, O_RDONLY | O_NOCTTY)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var attributes = termios()
        guard tcgetattr(descriptor, &attributes) == 0 else { return false }
        // Every flag that `cfmakeraw` clears must be clear, and the program
        // must read eight bits without parity. Checking only line editing and
        // echo would accept a terminal that still turns Control-C into a
        // signal or Return into a line feed.
        let cleared: [(flags: tcflag_t, mask: Int32)] = [
            (attributes.c_iflag, BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON),
            (attributes.c_oflag, OPOST),
            (attributes.c_lflag, ECHO | ECHONL | ICANON | ISIG | IEXTEN),
            (attributes.c_cflag, PARENB),
        ]
        return cleared.allSatisfy { $0.flags & tcflag_t($0.mask) == 0 }
            && attributes.c_cflag & tcflag_t(CSIZE) == tcflag_t(CS8)
    }

    /// The process identifiers of the children of the script's shell.
    public func childProcessIdentifiers() -> [pid_t] {
        let childLister = Process()
        childLister.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        childLister.arguments = ["-P", String(processIdentifier)]
        let pipe = Pipe()
        childLister.standardOutput = pipe
        guard (try? childLister.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        childLister.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { pid_t($0) }
    }

    /// Waits for the script to end.
    public func waitForExit(timeout: Duration = .seconds(15)) async -> ProgramExit? {
        let exitHolder = ExitHolder()
        let waiter = Task { exitHolder.set(await pseudoTerminal.waitForExit()) }
        defer { waiter.cancel() }
        _ = await eventually(timeout: timeout) { exitHolder.value != nil }
        return exitHolder.value
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

    private final class ExitHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: ProgramExit?
        var value: ProgramExit? { lock.withLock { stored } }
        func set(_ exit: ProgramExit) { lock.withLock { stored = exit } }
    }
}
