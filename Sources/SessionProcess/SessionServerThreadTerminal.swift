import AgentThreads
import ClaudeCodeAgent
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
        guard await threads.terminalSession(of: thread) == nil else { throw ThreadRequestError.openInTerminal }
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
        // The thread keeps the conversation, so its terminal does not come back after a restart.
        await records.exclude(summary.identifier)
        await threads.openedInTerminal(thread, session: summary.identifier, historyEnd: historyEnd)
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
