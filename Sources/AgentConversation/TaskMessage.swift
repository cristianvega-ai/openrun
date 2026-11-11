/// A message inside the task of a sub-agent.
public struct TaskMessage: Codable, Sendable, Hashable {
    /// The tool call that started the task.
    public var toolCallIdentifier: String
    public var text: String

    public init(toolCallIdentifier: String, text: String) {
        self.toolCallIdentifier = toolCallIdentifier
        self.text = text
    }
}
