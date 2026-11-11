/// A piece of the agent's text while it streams.
public struct AgentTextDelta: Codable, Sendable, Hashable {
    /// The identifier of the text that the piece belongs to. The complete
    /// text, `AgentText`, has the same identifier.
    public var itemIdentifier: String
    /// The new text, in Markdown, to add at the end.
    public var text: String

    public init(itemIdentifier: String, text: String) {
        self.itemIdentifier = itemIdentifier
        self.text = text
    }
}
