/// One part of the agent's answer in a transcript.
public struct AgentMessage: Codable, Sendable, Hashable {
    /// The text in Markdown. Only a view may give it form, and nothing may
    /// run it.
    public var text: String
    /// Whether the text has stopped to stream.
    public var isComplete: Bool

    public init(text: String, isComplete: Bool) {
        self.text = text
        self.isComplete = isComplete
    }
}
