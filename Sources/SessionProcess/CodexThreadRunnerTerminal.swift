import AgentConversation
import CodexAgent
import Foundation

/// Open in Terminal for a Codex thread (proposal 6): Codex in a terminal
/// goes on with the thread, and the chat takes the turns of the terminal
/// from the history of Codex.
extension CodexThreadRunner {
    /// The arguments of `codex` for the terminal of the thread.
    var terminalArguments: [String] {
        let sandbox = CodexSandbox(rawValue: record.permissionMode) ?? .workspaceWrite
        return sandbox.terminalArguments(thread: record.conversationIdentifier, model: record.model == Self.configuredModel ? nil : record.model)
    }

    /// The thread leaves the app-server before Codex starts in the
    /// terminal, because two programs on one thread would write its
    /// history at the same time. The turn stops, and the thread takes no
    /// message until the terminal ends.
    func leaveForTerminal() async {
        isInTerminal = true
        await stop()
        await thread?.leave()
        thread = nil
    }

    /// The terminal session ended. The turns that the user made there
    /// come into the events from the newest page of the history of
    /// Codex, and the thread takes messages again.
    func returnedFromTerminal() async {
        isInTerminal = false
        let page = try? await historyPage(cursor: nil)
        for event in transcript.turnsAfterKnown(in: page?.events ?? []) { emit(event) }
        await changed(self)
    }
}
