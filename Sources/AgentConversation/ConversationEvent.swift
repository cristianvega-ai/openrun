/// One event of an agent conversation, with the line it came from.
public struct ConversationEvent: Codable, Sendable, Hashable {
    public var kind: ConversationEventKind
    /// The line of the agent's output that gave the event. Events that the
    /// session process makes itself, such as a sent message, have none.
    /// One line can give several events, and each one carries the line.
    public var sourceLine: SourceLine?

    public init(_ kind: ConversationEventKind, sourceLine: SourceLine? = nil) {
        self.kind = kind
        self.sourceLine = sourceLine
    }
}
