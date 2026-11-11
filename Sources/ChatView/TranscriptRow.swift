/// One row of the transcript view.
///
/// A row is the unit that the view measures, shows and reuses. Several
/// rows can show one item, such as the parts of a long message, and one row
/// can show several items, such as a run of tool calls.
struct TranscriptRow: Equatable {
    enum Kind: Equatable {
        /// The note that earlier items exist, at the top.
        case earlierItems
        case userMessage(item: String)
        /// Blocks of an agent's message that are not code, as one text.
        case agentText(item: String, blocks: Range<Int>)
        /// One code block of an agent's message, in a box of its own.
        case agentCode(item: String, block: Int)
        /// A run of tool calls that shows as one compact group.
        case toolCalls(items: [String])
        case fileChange(item: String)
        case permissionRequest(item: String)
        case task(item: String)
        case notice(item: String)
        /// A turn that the user stopped or that failed.
        case turnEnd(item: String)
        case unknown(item: String)
        /// The mark that the agent works, at the bottom.
        case activity
    }

    /// Stable while the row lives, so the view keeps its place and its view.
    var key: String
    var kind: Kind

    /// The items of the transcript that the row shows.
    var items: [String] {
        switch kind {
        case .earlierItems, .activity: []
        case .toolCalls(let items): items
        case .userMessage(let item), .agentText(let item, _), .agentCode(let item, _), .fileChange(let item),
            .permissionRequest(let item), .task(let item), .notice(let item), .turnEnd(let item), .unknown(let item):
            [item]
        }
    }
}
