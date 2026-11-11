import AgentConversation

/// The start of a turn.
extension CodexAppServer {
    /// The most messages that wait for Codex to take them.
    static let pendingMessageLimit = 64

    func startTurn(_ turn: CodexTurn, thread: String) async throws {
        guard let state = threads[thread] else { throw CodexRequestError.threadIsClosed }
        // The message shows at once. When Codex takes it, its item comes
        // with the same identifier, and the chat marks it as taken.
        threads[thread]?.mapper.pendingMessageIdentifiers.append(turn.messageIdentifier)
        if (threads[thread]?.mapper.pendingMessageIdentifiers.count ?? 0) > Self.pendingMessageLimit {
            threads[thread]?.mapper.pendingMessageIdentifiers.removeFirst()
        }
        state.channel.add(ConversationEvent(.userMessage(turn.userMessage)))
        do {
            _ = try await request("turn/start", turn.parameters(thread: thread))
        } catch {
            threads[thread]?.mapper.pendingMessageIdentifiers.removeAll { $0 == turn.messageIdentifier }
            throw error
        }
    }
}
