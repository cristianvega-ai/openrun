/// The facts that an agent gives when its process starts a thread.
///
/// Claude Code repeats them when it takes each user message, and Codex
/// gives them when a thread starts or resumes. A later one replaces an
/// earlier one.
public struct AgentStart: Codable, Sendable, Hashable {
    /// The agent's own identifier of the conversation.
    public var conversationIdentifier: String?
    /// The model, as the agent resolved it, such as `claude-haiku-5-5`.
    public var model: String?
    /// The permission mode, in the agent's own words.
    public var permissionMode: String?
    /// The version of the agent program.
    public var agentVersion: String?
    /// The working folder of the agent.
    public var workingFolder: String?

    public init(
        conversationIdentifier: String? = nil, model: String? = nil, permissionMode: String? = nil,
        agentVersion: String? = nil, workingFolder: String? = nil
    ) {
        self.conversationIdentifier = conversationIdentifier
        self.model = model
        self.permissionMode = permissionMode
        self.agentVersion = agentVersion
        self.workingFolder = workingFolder
    }
}
