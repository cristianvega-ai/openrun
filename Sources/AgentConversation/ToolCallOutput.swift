/// Output of a running tool call as it comes, such as the output of a
/// command that Codex runs.
public struct ToolCallOutput: Codable, Sendable, Hashable {
    public var identifier: String
    /// The new output to add at the end.
    public var text: String

    public init(identifier: String, text: String) {
        self.identifier = identifier
        self.text = text
    }
}
