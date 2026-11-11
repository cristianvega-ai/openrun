/// Makes the view for each kind of row.
@MainActor enum TranscriptRowViews {
    static func make(for row: TranscriptRow) -> TranscriptRowView {
        switch row.kind {
        case .userMessage: UserMessageRowView()
        case .agentText: AgentTextRowView()
        case .agentCode: CodeBlockRowView()
        case .toolCalls: ToolCallsRowView()
        case .fileChange: FileChangeRowView()
        case .permissionRequest: PermissionRequestRowView()
        case .task, .notice, .turnEnd, .unknown: QuietRowView()
        default: TranscriptRowView()
        }
    }
}
