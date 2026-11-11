import AgentConversation
import AppKit

/// A permission request: the one loud row of the chat. While it waits, it
/// shows in full in its box. No key of the composer answers it, so a
/// message that the user types never allows a command by mistake. After
/// the answer, it folds to a quiet line.
final class PermissionRequestRowView: StackRowView {
    let box = PermissionRequestBoxView()
    let foldedLine = DisclosureLineView()
    private var requestIdentifier = ""

    override func configure(_ row: TranscriptRow, context: TranscriptRowContext) {
        super.configure(row, context: context)
        guard case .permissionRequest(let item)? = row.items.first.flatMap(context.item) else { return }
        let words = PermissionRequestWords(item, agentName: context.agentName)
        requestIdentifier = item.request.identifier
        setAccessibilityRole(.group)
        setAccessibilityLabel(item.isWaiting ? "Permission request: " + words.title : "Answered permission request")
        guard item.isWaiting else {
            let subject = words.subject.split(separator: "\n").joined(separator: " ")
            foldedLine.show(symbolName: "hand.raised", title: Self.outcome(of: item) + ": " + subject,
                            status: item.end?.message.map { "“\($0)”" }, palette: context.palette)
            setParts([Part(view: foldedLine)])
            return
        }
        box.show(words, agentName: context.agentName, isAnswered: context.answeredRequests.contains(requestIdentifier), palette: context.palette)
        box.answerAction = { [weak self] answer in self?.answer(answer) }
        setParts([Part(view: box)])
    }

    /// Tells VoiceOver of a new request once, also when its row is far from
    /// the screen and has no view.
    static func announce(_ item: PermissionRequestItem, context: TranscriptRowContext) {
        guard item.isWaiting, context.announcedRequests.insert(item.request.identifier).inserted else { return }
        let title = PermissionRequestWords(item, agentName: context.agentName).title
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: title, .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    static func outcome(of item: PermissionRequestItem) -> String {
        switch item.end?.outcome {
        case .allowed: "Allowed"
        case .denied: "Denied"
        case .timedOut: "Denied after the time limit"
        case .cancelled, nil: "Ended without an answer"
        }
    }

    private func answer(_ answer: ChatPermissionAnswer) {
        guard let context, context.answeredRequests.insert(requestIdentifier).inserted else { return }
        for control in [box.denyButton, box.allowButton, box.messageField] as [NSControl] { control.isEnabled = false }
        context.actions?.answerPermissionRequest(requestIdentifier, with: answer)
    }
}
