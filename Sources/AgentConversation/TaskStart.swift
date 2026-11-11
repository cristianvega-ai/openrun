/// The agent gave a task to a sub-agent.
public struct TaskStart: Codable, Sendable, Hashable {
    /// The agent's identifier of the task.
    public var identifier: String
    /// The tool call that started the task.
    public var toolCallIdentifier: String?
    public var description: String
    /// The kind of sub-agent, such as `general-purpose`.
    public var agentType: String?
    /// The instructions that the sub-agent got.
    public var prompt: String

    public init(identifier: String, toolCallIdentifier: String?, description: String, agentType: String?, prompt: String) {
        self.identifier = identifier
        self.toolCallIdentifier = toolCallIdentifier
        self.description = description
        self.agentType = agentType
        self.prompt = prompt
    }
}
