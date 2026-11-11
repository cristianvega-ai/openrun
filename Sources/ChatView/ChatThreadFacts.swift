/// The facts of a thread that the chat shows around its transcript.
///
/// Each fact shows in one place: the agent and the account in the top row,
/// and the model, the mode, the folder and the branch under the composer.
public struct ChatThreadFacts: Equatable, Hashable, Sendable {
    /// The chat keeps a draft for each thread under this identifier.
    public var threadIdentifier: String
    /// The title of the pane, such as the thread's name.
    public var title: String
    /// The agent's name, such as "Claude Code".
    public var agentName: String
    public var accountName: String?
    public var model: ChatChoice?
    public var models: [ChatChoice]
    public var permissionMode: ChatChoice?
    /// The modes that the menu offers: each mode up to the one of the
    /// settings (proposal 9 of 2026-11-10). A wider mode changes only in
    /// the settings window.
    public var permissionModes: [ChatChoice]
    /// The folder, as the user reads it, such as `~/Projects/openrun`.
    public var folder: String?
    public var branch: String?
    public var condition: ChatThreadCondition
    /// Whether the agent's history holds turns before the first item.
    public var hasEarlierHistory: Bool
    public var isLoadingEarlierHistory: Bool

    public init(
        threadIdentifier: String, title: String, agentName: String, accountName: String? = nil, model: ChatChoice? = nil,
        models: [ChatChoice] = [], permissionMode: ChatChoice? = nil, permissionModes: [ChatChoice] = [],
        folder: String? = nil, branch: String? = nil, condition: ChatThreadCondition = .ready,
        hasEarlierHistory: Bool = false, isLoadingEarlierHistory: Bool = false
    ) {
        self.threadIdentifier = threadIdentifier
        self.title = title
        self.agentName = agentName
        self.accountName = accountName
        self.model = model
        self.models = models
        self.permissionMode = permissionMode
        self.permissionModes = permissionModes
        self.folder = folder
        self.branch = branch
        self.condition = condition
        self.hasEarlierHistory = hasEarlierHistory
        self.isLoadingEarlierHistory = isLoadingEarlierHistory
    }
}
