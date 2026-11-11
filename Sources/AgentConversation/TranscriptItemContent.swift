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
