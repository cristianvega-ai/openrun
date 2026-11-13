import AgentThreads
import ClaudeCodeAgent
import CodexAgent
import Foundation
import SessionProtocol

/// Open in Terminal (proposal 6): the conversation of a thread goes to the
/// agent's own program in a terminal session, and comes back at its end.
extension SessionServer {
    /// Stops the headless agent first, because a second process on the
    /// conversation would split it in two. Then starts Claude Code on the
    /// same conversation in a new session, in the folder of the thread.
    func openInTerminal(_ thread: UUID, size: SessionSize) async throws -> ServerMessage {
        let record = try await threads.record(thread)
        // The registry gives no runner during a handoff, so the runner comes first.
        let runner = try await threads.running(for: thread)
        // The reservation comes before the first wait, so a second handoff fails at once.
        try await threads.reserveTerminal(thread)
        do {
            let result = try await handOff(record, runner: runner, size: size)
            await threads.finishTerminalHandoff(thread)
            return result
        } catch {
            await threads.finishTerminalHandoff(thread)
            throw error
        }
    }

    private func handOff(_ record: ThreadRecord, runner: any ThreadRunning, size: SessionSize) async throws -> ServerMessage {
        let thread = record.identifier
        if record.agent == .codex { return try await openCodexInTerminal(record, runner: runner, size: size) }
        guard let conversation = UUID(uuidString: record.conversationIdentifier), let mode = ClaudeCodePermissionMode(rawValue: record.permissionMode) else {
            throw ClaudeCodeLaunchError.invalidModel
        }
        let runner = try await threads.runner(for: thread)
        await runner.stop()
        await runner.endProcess()
        let settings = await agents.settings()
        let launch = try ClaudeCodeLaunch(
            model: record.model, permissionMode: mode, conversation: record.hasConversation ? .resume(conversation) : .new(conversation),
            hookCommand: settings.hookCommand, hookArguments: settings.hookArguments)
        var additions = ["OPENRUN_THREAD": record.identifier.uuidString.lowercased()]
        if let account = record.account { additions["CLAUDE_CONFIG_DIR"] = account.settingsFolder }
        let environment = ClaudeCodeEnvironment.make(base: settings.environment, additions: additions)
        // The turns of the terminal start where the history file ends now.
        let historyEnd = ThreadHistory.fileSize(of: record, environment: settings.environment)
        let summary = try await registry.create(folder: record.folder, command: [settings.program] + launch.terminalArguments, size: size, environment: environment)
        return await openedInTerminal(thread, session: summary, historyEnd: historyEnd)
    }

    /// Codex has the conversation under the identifier of its thread.
    /// The thread leaves the app-server, and `codex resume` goes on with
    /// it in a new session, under the account of the thread.
    private func openCodexInTerminal(_ record: ThreadRecord, runner: any ThreadRunning, size: SessionSize) async throws -> ServerMessage {
        guard record.hasConversation, UUID(uuidString: record.conversationIdentifier) != nil,
              let runner = runner as? CodexThreadRunner else { throw ThreadRequestError.noTurnYet }
        await runner.leaveForTerminal()
        let settings = await agents.settings()
        var environment = settings.environment
        if let account = record.account { environment["CODEX_HOME"] = account.settingsFolder }
        do {
            let command = [settings.codexProgram] + (await runner.terminalArguments)
            let summary = try await registry.create(folder: record.folder, command: command, size: size, environment: environment)
            return await openedInTerminal(record.identifier, session: summary, historyEnd: 0)
        } catch {
            // No terminal started, so the app-server takes the thread again.
            await runner.returnedFromTerminal()
            throw error
        }
    }

    private func openedInTerminal(_ thread: UUID, session summary: SessionSummary, historyEnd: UInt64) async -> ServerMessage {
        // The thread keeps the conversation, so its terminal does not come back after a restart.
        await records.exclude(summary.identifier)
        guard await threads.openedInTerminal(thread, session: summary.identifier, historyEnd: historyEnd) else {
            _ = await registry.session(for: summary.identifier)?.terminate()
            return Self.refusal("The thread closed while the terminal started.")
        }
        // A program that ended at once ended before the thread knew its session.
        if await registry.session(for: summary.identifier) == nil { await threads.sessionEnded(summary.identifier) }
        SessionLog.write("Opened a thread in the terminal session \(summary.identifierText)")
        return .sessionCreated(summary)
    }

    /// Ends the terminal session of a thread. The end of the session
    /// brings the thread back, as when the user leaves the agent there.
    func returnFromTerminal(_ thread: UUID) async throws -> ServerMessage {
        guard let session = await threads.terminalSession(of: thread) else { throw ThreadRequestError.notInTerminal }
        _ = await registry.session(for: session)?.terminate()
        return .acknowledged
    }
}
