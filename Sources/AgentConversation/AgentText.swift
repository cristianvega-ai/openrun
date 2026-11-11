/// The complete text of one part of the agent's answer, in Markdown.
///
/// It replaces the pieces that streamed before it with the same identifier.
public struct AgentText: Codable, Sendable, Hashable {
    public var itemIdentifier: String
    public var text: String

    public init(itemIdentifier: String, text: String) {
        self.itemIdentifier = itemIdentifier
        self.text = text
    }
}
