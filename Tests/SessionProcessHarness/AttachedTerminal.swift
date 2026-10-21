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
    /// The terminal, opened while the shell runs. See `openTerminal(of:)`.
    private let terminalDescriptor: Int32
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
        terminalDescriptor = Self.openTerminal(of: pseudoTerminal)
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

    deinit {
        if terminalDescriptor >= 0 { close(terminalDescriptor) }
    }

    /// The system gives the number of an ended terminal to the next new
    /// terminal, often one of a test that runs beside this one. A call
    /// through the path after the shell ended, such as a `resumeOutput` in
    /// a `defer`, could then restart output that the other test holds back.
    /// A descriptor that was opened while the shell ran keeps to this
    /// terminal: when the shell ends, the system revokes it, and later calls
    /// through it fail.
    private static func openTerminal(of pseudoTerminal: PseudoTerminal) -> Int32 {
        // O_NOCTTY keeps the test from adopting the terminal.
        let descriptor = open(pseudoTerminal.terminalPath, O_RDWR | O_NOCTTY | O_CLOEXEC)
        // The number is free only after the shell was reaped, so a shell that
        // is still there proves that the open reached this terminal.
        guard descriptor >= 0, kill(pseudoTerminal.processIdentifier, 0) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            return -1
        }
        return descriptor
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

    /// Stops the program's output from reaching this terminal, as a slow
    /// terminal window does. The program blocks once the terminal's output
    /// queue is full. Nothing is lost: `resumeOutput` lets it flow again, and
    /// the screen then shows all of it.
    ///
    /// The pseudo terminal reader of this class cannot do this, because it
    /// reads at once and keeps the bytes in memory. The terminal itself
    /// holds the output back instead.
    public func pauseOutput() {
        clearAnyKeyRestart()
        tcflow(terminalDescriptor, TCOOFF)
    }

    /// `cfmakeraw` leaves IXANY set. With it, any key that the terminal reads,
    /// such as the typed detach key, restarts the output that `pauseOutput`
    /// stopped, and the test would no longer hold the output back at the
    /// moment it types the key.
    private func clearAnyKeyRestart() {
        var attributes = termios()
        guard tcgetattr(terminalDescriptor, &attributes) == 0 else { return }
        attributes.c_iflag &= ~tcflag_t(IXANY)
        tcsetattr(terminalDescriptor, TCSANOW, &attributes)
    }

    /// Lets the output that `pauseOutput` held back flow again.
    public func resumeOutput() {
        tcflow(terminalDescriptor, TCOON)
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
        var attributes = termios()
        guard tcgetattr(terminalDescriptor, &attributes) == 0 else { return false }
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

    /// The child of the script's shell that runs the program with this name.
    /// The first child is not the tool while the script still runs a command
    /// substitution, such as `stty -g`, so a test that signals "the first
    /// child" can signal a process that is about to end.
    public func childProcessIdentifier(named name: String) -> pid_t? {
        let childLister = Process()
        childLister.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        childLister.arguments = ["-P", String(processIdentifier), "-x", name]
        let pipe = Pipe()
        childLister.standardOutput = pipe
        guard (try? childLister.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        childLister.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { pid_t($0) }.first
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
