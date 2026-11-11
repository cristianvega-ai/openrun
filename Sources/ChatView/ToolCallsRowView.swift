import AgentConversation
import AppKit

/// A run of tool calls as compact lines. A line opens to the input and the
/// start of the output of its call. A run of more than three calls shows
/// as one line that counts them and opens to the calls.
final class ToolCallsRowView: StackRowView {
    private var lines: [String: DisclosureLineView] = [:]
    private var details: [String: DetailBoxView] = [:]

    override func configure(_ row: TranscriptRow, context: TranscriptRowContext) {
        super.configure(row, context: context)
        let calls = row.items.compactMap { identifier -> (String, ToolCallItem)? in
            guard case .toolCall(let call)? = context.item(identifier) else { return nil }
            return (identifier, call)
        }
        var newParts: [Part] = []
        var shownCalls = calls
        var indentation: CGFloat = 0
        if calls.count > 3 {
            let isOpen = context.openedParts.contains(row.key)
            let summary = line(row.key, context: context)
            let isRunning = calls.contains { $0.1.state == .running || $0.1.state == .preparing }
            let title = ToolCallSummary.title(ofRun: calls.map(\.1))
            summary.show(symbolName: "list.bullet", title: title, status: isRunning ? "Running" : nil, palette: context.palette)
            summary.isOpen = isOpen
            newParts.append(Part(view: summary))
            shownCalls = isOpen ? calls : []
            indentation = 24
        }
        for (identifier, call) in shownCalls {
            let summary = ToolCallSummary(call)
            let callLine = line(identifier, context: context)
            callLine.show(symbolName: summary.symbolName, title: summary.title, status: summary.status, palette: context.palette)
            callLine.isOpen = context.openedParts.contains(identifier)
            newParts.append(Part(view: callLine, indentation: indentation))
            guard callLine.isOpen else { continue }
            let detail = details[identifier] ?? DetailBoxView()
            details[identifier] = detail
            detail.show(ToolCallSummary.detail(of: call, subject: summary.subject), palette: context.palette)
            newParts.append(Part(view: detail, indentation: indentation))
        }
        setParts(newParts)
        setAccessibilityRole(.group)
        setAccessibilityLabel(calls.count == 1 ? "Tool call" : "\(calls.count) tool calls")
    }

    private func line(_ part: String, context: TranscriptRowContext) -> DisclosureLineView {
        let line = lines[part] ?? DisclosureLineView()
        lines[part] = line
        line.action = { [weak self, weak context] in
            guard let self else { return }
            context?.actions?.toggle(part, in: self)
        }
        return line
    }
}
