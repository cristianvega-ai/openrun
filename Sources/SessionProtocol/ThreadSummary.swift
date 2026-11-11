import Foundation

/// What a client needs to know about an agent thread to list it
/// (decisions of 2026-11-10). The protocol keeps its own plain type, so a
/// client needs no other module of OpenRun to read it.
public struct ThreadSummary: Codable, Equatable, Sendable {
    public var identifier: UUID
    /// The agent, such as `claude-code`.
    public var agent: String
    /// The working folder of the agent.
    public var folder: String
    public var model: String
    /// The permission mode, in the agent's own word, such as `default`.
    public var permissionMode: String
    /// The name that the user gave.
    public var name: String?
    /// The start of the first user message, until the thread has a name.
    public var title: String?
    /// The name of the account, or `nil` for the account of the login shell.
    public var accountName: String?
    public var createdAt: Date
    public var lastActivityAt: Date
    /// `idle`, `inProgress`, `needsUser`, `finishedTurn` or `failed`. A
    /// word of a later build is a state that this client does not know.
    public var state: String
    /// Whether the process of the agent runs now.
    public var isProcessRunning: Bool
    /// The messages that wait for the agent to take them.
    public var waitingMessageCount: Int
    /// The project that holds the folder of the thread, as for a session.
    public var projectIdentifier: UUID?

    public init(
        identifier: UUID, agent: String, folder: String, model: String, permissionMode: String, name: String? = nil, title: String? = nil,
        accountName: String? = nil, createdAt: Date, lastActivityAt: Date, state: String = "idle", isProcessRunning: Bool = false,
        waitingMessageCount: Int = 0, projectIdentifier: UUID? = nil
    ) {
        (self.identifier, self.agent, self.folder, self.model, self.permissionMode) = (identifier, agent, folder, model, permissionMode)
        (self.name, self.title, self.accountName, self.createdAt, self.lastActivityAt) = (name, title, accountName, createdAt, lastActivityAt)
        (self.state, self.isProcessRunning, self.waitingMessageCount, self.projectIdentifier) = (state, isProcessRunning, waitingMessageCount, projectIdentifier)
    }

    /// The identifier in lower case, as for a session.
    public var identifierText: String {
        SessionSummary.text(for: identifier)
    }
}
