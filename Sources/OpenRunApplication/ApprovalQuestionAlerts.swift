import AppKit
import SessionConnection
import SessionProtocol

/// Shows the approval questions one at a time, in the order they came, and
/// sends each answer of the user. A question that ends before the user
/// answers goes away with no answer.
@MainActor
final class ApprovalQuestionAlerts {
    typealias Answer = @Sendable (_ identifier: UUID, _ allows: Bool) -> Void
    /// Runs the modal loop of an alert. Tests pass their own, because a test
    /// cannot answer a real alert.
    typealias RunModal = @MainActor (NSAlert) -> NSApplication.ModalResponse
    /// Ends the modal loop of an alert that is open, with `.abort`.
    typealias StopModal = @MainActor (NSAlert) -> Void

    private var waiting: [ApprovalQuestion] = []
    private var shown: (identifier: UUID, alert: NSAlert)?
    private let answer: Answer
    private let runModal: RunModal
    private let stopModal: StopModal

    init(answer: @escaping Answer, runModal: @escaping RunModal = ModalAlert.runStandardModal, stopModal: @escaping StopModal = ApprovalQuestionAlerts.stopStandardModal) {
        self.answer = answer
        self.runModal = runModal
        self.stopModal = stopModal
    }

    func handle(_ event: ApprovalQuestionReceiver.Event) {
        switch event {
        case .question(let question):
            waiting.append(question)
            showNextLater()
        case .ended(let identifier):
            waiting.removeAll { $0.identifier == identifier }
            if let shown, shown.identifier == identifier { stopModal(shown.alert) }
        case .closed, .failed:
            // The session process has ended the questions of this connection.
            waiting.removeAll()
            if let shown { stopModal(shown.alert) }
        }
    }

    /// A modal loop inside a block of the main queue would hold that queue,
    /// and attached windows would lose their output (see `ModalAlert`). A
    /// run loop block is no block of that queue.
    private func showNextLater() {
        guard shown == nil else { return }
        RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated { self.showNext() } }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private func showNext() {
        guard shown == nil, !waiting.isEmpty else { return }
        let question = waiting.removeFirst()
        let words = ApprovalQuestionWords(question)
        let alert = NSAlert()
        alert.messageText = words.title
        alert.informativeText = words.message
        for button in words.buttons { alert.addButton(withTitle: button) }
        shown = (question.identifier, alert)
        NSApp.requestUserAttention(.criticalRequest)
        let response = runModal(alert)
        shown = nil
        switch response {
        case .alertFirstButtonReturn: answer(question.identifier, false)
        case .alertSecondButtonReturn: answer(question.identifier, true)
        default: break
        }
        if !waiting.isEmpty { showNextLater() }
    }

    static func stopStandardModal(_ alert: NSAlert) {
        if NSApp.modalWindow === alert.window { NSApp.stopModal(withCode: .abort) }
    }
}
