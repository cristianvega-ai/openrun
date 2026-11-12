import Foundation
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Testing

/// Open in Terminal (proposal 6), through the socket of a real session
/// process. The fake agent stands in for Claude Code in the terminal too.
@Suite struct ThreadTerminalTests {
    private let size = SessionSize(columns: 80, rows: 24)

    @Test func aThreadGoesToATerminalSessionAndComesBackWithItsTurns() async throws {
        let settings = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: settings) }
        // The fake agent in the terminal adds this turn to the history of the conversation.
        let turn = FakeAgentSettings.fixtures.appending(path: "history.jsonl").path
        let process = try FakeAgentSettings.sessionProcess(environment: ["CLAUDE_CONFIG_DIR": settings.path, "FAKE_AGENT_TERMINAL_TURN": turn])
        defer { process.stop() }
        let client = try SessionClient(location: try SocketLocation(path: process.socketPath))
        let thread = try client.createThread(agent: "claude-code", folder: process.directory.path).identifier
        _ = try client.sendThreadMessage(thread, text: "One.")
        #expect(await eventually { (try? client.threads().first?.state) == "finishedTurn" })

        let session = try client.openThreadInTerminal(thread, size: size)
        #expect(session.command.contains("--resume") && !session.command.contains("-p") && session.command.last == "default")
        let open = try #require(try client.threads().first)
        #expect(open.terminalSession == session.identifier && !open.isProcessRunning && session.folder == open.folder)
        #expect(await eventually { (try? process.runCommand(["read", session.identifierText]).standardOutput.contains("The fake agent runs in a terminal")) == true })
        // The conversation has one owner at a time.
        #expect(throws: SessionConnectionError.self) { try client.sendThreadMessage(thread, text: "Two.") }
        #expect(throws: SessionConnectionError.self) { try client.openThreadInTerminal(thread, size: size) }

        try client.returnThreadFromTerminal(thread)
        #expect(await eventually { (try? client.threads().first.map { $0.terminalSession == nil }) == true })
        #expect(try client.summaries().isEmpty)
        // The turn of the terminal came into the events of the thread, after the turn before it.
        let text = try process.runCommand(["thread", "read", SessionSummary.text(for: thread)]).standardOutput
        #expect(text.hasPrefix("You:\nOne.\n\nAgent:\nok\n\nYou:\nRun the command `touch held.txt` with your Bash tool."))
        #expect(throws: SessionConnectionError.self) { try client.returnThreadFromTerminal(thread) }
        // The thread takes messages again.
        _ = try client.sendThreadMessage(thread, text: "Three.")
        #expect(await eventually { (try? client.threads().first?.isProcessRunning) == true })
    }

    /// The fake app-server is no Codex for a terminal: it ends at once
    /// there, and the thread comes back with the turns of the history.
    @Test func aCodexThreadGoesToATerminalSessionAndComesBack() async throws {
        let mark = NSTemporaryDirectory() + "fake-codex-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: mark) }
        let fixtures = URL(fileURLWithPath: "../CodexAgentTests/Fixtures", relativeTo: URL(fileURLWithPath: #filePath)).standardizedFileURL
        func paths(_ names: [String]) -> String { names.map { fixtures.appending(path: $0 + ".jsonl").path }.joined(separator: ":") }
        let fake = RunningSessionProcess.productsDirectory.appendingPathComponent("fake-codex").path
        let process = try RunningSessionProcess(arguments: ["--codex-program", fake, "--own-environment-for-agents"], environment: [
            "FAKE_CODEX_SCRIPTS": paths(["handshake", "thread-start", "plain-turn", "unsubscribe"]), "FAKE_CODEX_IGNORED_MEMBERS": "cwd",
            "FAKE_CODEX_RESTART_SCRIPTS": paths(["handshake", "resume", "history"]), "FAKE_CODEX_RESTART_MARK": mark,
        ])
        defer { process.stop() }
        let client = try SessionClient(location: try SocketLocation(path: process.socketPath))
        let thread = try client.createThread(agent: "codex", folder: process.directory.path).identifier
        // Codex goes on with a conversation, so the thread needs a turn first.
        #expect(throws: SessionConnectionError.self) { try client.openThreadInTerminal(thread, size: size) }
        _ = try client.sendThreadMessage(thread, text: "Reply with the single word ok.")
        #expect(await eventually { (try? client.threads().first?.state) == "finishedTurn" })
        let session = try client.openThreadInTerminal(thread, size: size)
        #expect(session.command == [fake, "resume", "00000000-0000-7000-8000-000000000001", "--sandbox", "workspace-write"])
        #expect(await eventually { (try? client.threads().first.map { $0.terminalSession == nil }) == true })
        let text = try process.runCommand(["thread", "read", SessionSummary.text(for: thread)]).standardOutput
        // The three turns of the history come after the turn of the chat, the oldest first.
        #expect(text.hasPrefix("You:\nReply with the single word ok.\n\nAgent:\nok\n\nYou:\nWrite the numbers from 1 to 300"))
        #expect(text.contains("\n\nYou:\nRun the command `touch x4.txt` with your shell tool.\n\nNotice: Codex keeps only"))
        // The thread takes messages again.
        _ = try client.sendThreadMessage(thread, text: "More.")
    }

    @Test func aNewThreadStartsItsConversationInTheTerminal() async throws {
        let process = try FakeAgentSettings.sessionProcess()
        defer { process.stop() }
        let client = try SessionClient(location: try SocketLocation(path: process.socketPath))
        let thread = try client.createThread(agent: "claude-code", folder: process.directory.path, model: "sonnet").identifier
        let session = try client.openThreadInTerminal(thread, size: size)
        #expect(Array(session.command.dropFirst()) == ["--session-id", SessionSummary.text(for: thread), "--model", "sonnet", "--permission-mode", "default"])
        // The user ends the agent in the terminal, and the thread comes back.
        _ = try process.runCommand(["kill", session.identifierText])
        #expect(await eventually { (try? client.threads().first.map { $0.terminalSession == nil }) == true })
    }
}
