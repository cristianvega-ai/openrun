/// The task of a sub-agent ended.
public struct TaskEnd: Codable, Sendable, Hashable {
    public var identifier: String
    public var toolCallIdentifier: String?
    /// The agent's word for the end, such as `completed` or `failed`.
    public var status: String
    /// A short summary of the result, when the agent gives one.
    public var summary: String?

    public init(identifier: String, toolCallIdentifier: String?, status: String, summary: String?) {
        self.identifier = identifier
        self.toolCallIdentifier = toolCallIdentifier
        self.status = status
        self.summary = summary
    }
}
