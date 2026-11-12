import AgentConversation
import MarkdownText

/// Makes the rows of the view from the items of a transcript.
///
/// It keeps the parsed Markdown of each agent message, and parses again
/// only the messages that a change names, so text that streams into one
/// message costs the same however long the transcript is.
struct TranscriptRowBuilder {
    private(set) var documents: [String: MarkdownDocument] = [:]
    private var segments: [String: [MessageSegment]] = [:]

    /// The rows of `transcript`.
    /// - Parameters:
    ///   - changedItems: The items whose content changed since the last
    ///     call. Nil means that any item can have changed.
    ///   - showsEarlierItems: Whether the row for earlier items comes first.
    mutating func rows(for transcript: Transcript, changedItems: Set<String>?, showsEarlierItems: Bool) -> [TranscriptRow] {
        let items = transcript.items
        let hidden = Self.toolCallsShownElsewhere(in: items)
        var rows: [TranscriptRow] = showsEarlierItems ? [TranscriptRow(key: "earlier", kind: .earlierItems)] : []
        var toolRun: [String] = []
        func endToolRun() {
            if let first = toolRun.first { rows.append(TranscriptRow(key: "group:" + first, kind: .toolCalls(items: toolRun))) }
            toolRun = []
        }
        var present = Set<String>()
        // The text of the notice just before an item, when a notice is there.
        var noticeBefore: String?
        for item in items {
            let identifier = item.identifier
            defer { if case .notice(let notice) = item.content { noticeBefore = notice.text } else { noticeBefore = nil } }
            if case .toolCall = item.content {
                if !hidden.contains(identifier) { toolRun.append(identifier) }
                continue
            }
            endToolRun()
            switch item.content {
            case .userMessage: rows.append(TranscriptRow(key: identifier, kind: .userMessage(item: identifier)))
            case .agentMessage(let message):
                present.insert(identifier)
                let isChanged = changedItems?.contains(identifier) ?? true
                appendMessage(identifier, message, isChanged: isChanged || documents[identifier] == nil, to: &rows)
            case .fileChange: rows.append(TranscriptRow(key: identifier, kind: .fileChange(item: identifier)))
            case .permissionRequest: rows.append(TranscriptRow(key: identifier, kind: .permissionRequest(item: identifier)))
            case .task: rows.append(TranscriptRow(key: identifier, kind: .task(item: identifier)))
            case .notice: rows.append(TranscriptRow(key: identifier, kind: .notice(item: identifier)))
            case .turnEnd(let end):
                // A turn that ends as it should needs no row, and neither
                // does a failed turn whose reason the notice before it told.
                let isTold = end.outcome == .failed && end.errorText != nil && end.errorText == noticeBefore
                if end.outcome != .done, !isTold { rows.append(TranscriptRow(key: identifier, kind: .turnEnd(item: identifier))) }
            case .unknown: rows.append(TranscriptRow(key: identifier, kind: .unknown(item: identifier)))
            case .toolCall: break
            }
        }
        endToolRun()
        if transcript.state == .inProgress { rows.append(TranscriptRow(key: "activity", kind: .activity)) }
        if documents.count > present.count {
            documents = documents.filter { present.contains($0.key) }
            segments = segments.filter { present.contains($0.key) }
        }
        return rows
    }

    private mutating func appendMessage(_ identifier: String, _ message: AgentMessage, isChanged: Bool, to rows: inout [TranscriptRow]) {
        if isChanged {
            var document = documents[identifier] ?? MarkdownDocument(text: "", isComplete: false)
            if document.text != message.text || document.isComplete != message.isComplete {
                document.update(text: message.text, isComplete: message.isComplete)
                documents[identifier] = document
                segments[identifier] = MessageSegment.segments(of: document.blocks)
            } else if documents[identifier] == nil {
                documents[identifier] = document
                segments[identifier] = []
            }
        }
        for (index, segment) in (segments[identifier] ?? []).enumerated() {
            let key = identifier + "#\(index)"
            switch segment {
            case .text(let blocks): rows.append(TranscriptRow(key: key, kind: .agentText(item: identifier, blocks: blocks)))
            case .code(let block): rows.append(TranscriptRow(key: key, kind: .agentCode(item: identifier, block: block)))
            }
        }
    }

    /// The tool calls that another row shows: a call that changed a file
    /// shows as its file change, a call that started a sub-agent shows as
    /// its task, and a call that the user did not allow shows as its
    /// permission request.
    static func toolCallsShownElsewhere(in items: [TranscriptItem]) -> Set<String> {
        var hidden = Set<String>()
        for item in items {
            switch item.content {
            case .fileChange(let change): change.toolCallIdentifier.map { hidden.insert("tool:" + $0) }
            case .task(let task): (task.start?.toolCallIdentifier ?? task.end?.toolCallIdentifier).map { hidden.insert("tool:" + $0) }
            case .permissionRequest(let permission) where permission.end?.outcome != .allowed:
                permission.request.toolCallIdentifier.map { hidden.insert("tool:" + $0) }
            default: break
            }
        }
        return hidden
    }
}
