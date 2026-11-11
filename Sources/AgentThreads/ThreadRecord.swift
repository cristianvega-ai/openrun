import Foundation

/// What OpenRun keeps of an agent thread (decision of 2026-11-10). The
/// conversation itself stays in the agent's own history, and OpenRun
/// keeps no copy of it (proposal 3).
public struct ThreadRecord: Codable, Equatable, Sendable {
    /// Given by OpenRun. It stays the same for the life of the thread.
    public let identifier: UUID
    public let agent: ThreadAgent
    /// The agent's own identifier of the conversation. For Claude Code,
    /// OpenRun chooses it at the first start, so it is known at once.
    public var conversationIdentifier: String
    /// Whether the agent started the conversation at least once. The
    /// first start gives the identifier, and each later start resumes.
    public var hasConversation = false
    /// `nil` means the account that the login shell of the user gives.
    public var account: ThreadAccount?
    /// The working folder of the agent, an absolute path.
    public var folder: String
    public var model: String
    /// The permission mode, in the agent's own word, such as `default`.
    public var permissionMode: String
    /// The name that the user gave.
    public var name: String?
    /// The start of the first user message, which a list shows until the
    /// thread has a name.
    public var title: String?
    public var createdAt: Date
    public var lastActivityAt: Date

    public init(
        identifier: UUID = UUID(), agent: ThreadAgent, conversationIdentifier: String? = nil, account: ThreadAccount? = nil,
        folder: String, model: String, permissionMode: String, name: String? = nil, createdAt: Date = Date()
    ) {
        self.identifier = identifier
        self.agent = agent
        self.conversationIdentifier = conversationIdentifier ?? identifier.uuidString.lowercased()
        (self.account, self.folder, self.model, self.permissionMode, self.name) = (account, folder, model, permissionMode, name)
        (self.createdAt, lastActivityAt) = (createdAt, createdAt)
    }
}
