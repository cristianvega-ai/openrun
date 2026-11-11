import AgentConversation

/// One page of the earlier turns of a Codex thread.
public struct CodexHistoryPage: Sendable, Hashable {
    /// The events of the turns of the page, oldest first. A page that is
    /// older comes before it in a chat.
    public var events: [ConversationEvent]
    /// The cursor of the page of older turns, or nil after the first turn.
    public var olderCursor: String?

    public init(events: [ConversationEvent], olderCursor: String?) {
        self.events = events
        self.olderCursor = olderCursor
    }
}
