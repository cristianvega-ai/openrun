/// What one item of a transcript shows.
public enum TranscriptItemContent: Codable, Sendable, Hashable {
    case userMessage(UserMessage)
    case agentMessage(AgentMessage)
    case toolCall(ToolCallItem)
    case fileChange(FileChange)
    case permissionRequest(PermissionRequestItem)
    case task(TaskItem)
    case turnEnd(TurnEnd)
    case notice(Notice)
    /// A plain row for a line that this version cannot read (proposal 4).
    case unknown(UnknownLine)
}

extension TranscriptItemContent {
    /// Holds no text, so it costs nothing to put in place for a moment.
    private static let placeholder = TranscriptItemContent.notice(Notice(level: .information, text: ""))

    // Each change takes the payload out first, so its text has one owner
    // and grows in place. Text that streams in many small pieces would
    // otherwise be copied whole for each piece.

    mutating func modifyUserMessage(_ body: (inout UserMessage) -> Void) {
        guard case .userMessage(var message) = self else { return }
        self = Self.placeholder
        body(&message)
        self = .userMessage(message)
    }

    mutating func modifyAgentMessage(_ body: (inout AgentMessage) -> Void) {
        guard case .agentMessage(var message) = self else { return }
        self = Self.placeholder
        body(&message)
        self = .agentMessage(message)
    }

    mutating func modifyToolCall(_ body: (inout ToolCallItem) -> Void) {
        guard case .toolCall(var call) = self else { return }
        self = Self.placeholder
        body(&call)
        self = .toolCall(call)
    }

    mutating func modifyPermissionRequest(_ body: (inout PermissionRequestItem) -> Void) {
        guard case .permissionRequest(var item) = self else { return }
        self = Self.placeholder
        body(&item)
        self = .permissionRequest(item)
    }

    mutating func modifyTask(_ body: (inout TaskItem) -> Void) {
        guard case .task(var task) = self else { return }
        self = Self.placeholder
        body(&task)
        self = .task(task)
    }
}
