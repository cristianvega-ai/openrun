import Foundation
import PseudoTerminal
import SessionProtocol
import Synchronization
import TerminalEmulation

actor Session {
    /// The line limit of the scrollback that every session keeps.
    static let scrollbackLimit = 10_000

    private(set) var summary: SessionSummary
    private let pseudoTerminal: PseudoTerminal
    private let terminal: Terminal
    private var runTask: Task<Void, Never>?
    private let onFinish: @Sendable (UUID) async -> Void

    /// Creates the terminal, then starts the program.
    ///
    /// The program starts last, so nothing can fail after it runs. A failure
    /// before it leaves no program running without a session.
    init(
        summary: SessionSummary,
        launch: ProgramLaunch,
        onFinish: @escaping @Sendable (UUID) async -> Void,
    ) throws {
        self.summary = summary
        self.onFinish = onFinish
        terminal = try Terminal(size: TerminalSize(summary.size), scrollbackLimit: Self.scrollbackLimit)
        let pseudoTerminal = try PseudoTerminal(launching: launch)
        self.pseudoTerminal = pseudoTerminal
    }

    /// Starts reading the program's output. Call once, right after creating.
    func start() {
        runTask = Task { await self.run() }
    }

    /// Types bytes into the program.
    ///
    /// Waits while the program's input backlog is full. The wait happens
    /// outside the actor, so the session goes on with its output, attaching,
    /// and ending meanwhile.
    ///
    /// - Throws: `PseudoTerminalError.programEnded` when the program ends
    ///   before the bytes are in the backlog.
    nonisolated func type(_ bytes: [UInt8]) async throws {
        try await pseudoTerminal.type(bytes)
    }

    /// The text on the screen, or on the screen and above it.
    func screenText(includeScrollback: Bool) throws -> String {
        let bytes = try terminal.formatted(.plainText, extent: includeScrollback ? .withScrollback : .visible)
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Private

    private func run() async {
        for await bytes in pseudoTerminal.output {
            terminal.write(bytes)
            pseudoTerminal.markOutputConsumed(bytes.count)
            // A program that asks questions and never reads the answers waits
            // here, in its own output, instead of growing the input backlog.
            await pseudoTerminal.waitForAnswerRoom()
            // A steady stream never suspends this loop, and the actor would
            // serve nobody else. Yielding lets attach, read and kill run.
            await Task.yield()
        }
        await onFinish(summary.identifier)
    }
}

extension TerminalSize {
    fileprivate init(_ size: SessionSize) {
        self.init(columns: size.columns, rows: size.rows)
    }
}
