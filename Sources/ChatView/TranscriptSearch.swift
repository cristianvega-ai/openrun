import AgentConversation
import Foundation

/// Finds text in the rows of a transcript, for Command-F.
///
/// It looks at the words that each row shows, so a match is always text
/// that the user can see once the row opens.
@MainActor enum TranscriptSearch {
    struct Match: Equatable {
        var rowKey: String
        /// The place of the match in the text of the row.
        var range: NSRange
    }

    static func matches(of query: String, in rows: [TranscriptRow], context: TranscriptRowContext) -> [Match] {
        guard !query.isEmpty else { return [] }
        var matches: [Match] = []
        for row in rows {
            let text = plainText(of: row, context: context) as NSString
            var start = 0
            while start < text.length {
                let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: NSRange(location: start, length: text.length - start))
                guard found.location != NSNotFound else { break }
                matches.append(Match(rowKey: row.key, range: found))
                start = found.location + max(found.length, 1)
            }
        }
        return matches
    }

    /// The words that a row shows.
    static func plainText(of row: TranscriptRow, context: TranscriptRowContext) -> String {
        switch row.kind {
        case .agentText(let item, let blocks): return context.text(ofBlocks: blocks, in: item).string
        case .agentCode(let item, let index):
            guard let blocks = context.documents[item]?.blocks, blocks.indices.contains(index),
                case .code(_, let code, _) = blocks[index].kind else { return "" }
            return code
        case .toolCalls(let items):
            return items.compactMap { item -> String? in
                guard case .toolCall(let call)? = context.item(item) else { return nil }
                return ToolCallSummary(call).title
            }.joined(separator: "\n")
        default:
            guard let content = row.items.first.flatMap(context.item) else { return "" }
            switch content {
            case .userMessage(let message): return message.text
            case .fileChange(let change): return change.path
            case .permissionRequest(let item): return PermissionRequestWords(item, agentName: context.agentName).subject
            default: return QuietLine(content)?.title ?? ""
            }
        }
    }
}
