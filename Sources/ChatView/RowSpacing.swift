import CoreGraphics

/// The space above each row, which gives the chat its rhythm.
///
/// A new message of the user opens a turn with the most space. The parts
/// of one answer stay close, and quiet lines, such as tool calls, stay
/// closer still, so they read as one run.
enum RowSpacing {
    static let top: CGFloat = 24
    static let bottom: CGFloat = 28

    static func above(_ row: TranscriptRow, after previous: TranscriptRow?) -> CGFloat {
        guard let previous else { return top }
        switch (previous.kind, row.kind) {
        case (_, .userMessage): return 28
        case (.userMessage, _): return 18
        case (.agentText, .agentText), (.agentText, .agentCode), (.agentCode, .agentText), (.agentCode, .agentCode): return 11
        case (_, .permissionRequest), (.permissionRequest, _): return 14
        case (.agentText, _), (.agentCode, _), (_, .agentText), (_, .agentCode): return 12
        default: return 6
        }
    }
}
