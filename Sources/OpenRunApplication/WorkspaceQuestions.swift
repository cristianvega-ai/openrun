import AppKit

/// The sheets of the main window: a failure, and the question before a close.
extension Workspace {
    /// Shows why a request failed, as a sheet on the window. The text
    /// comes from the session process or the system, and shows as it is.
    func showFailureSheet(title: String, message: String) {
        let alert = NSAlert()
        (alert.messageText, alert.informativeText) = (title, message)
        alert.addButton(withTitle: "OK")
        present(alert) { _ in }
    }

    /// Asks before the close of a session that still runs a program. The
    /// first button is the default one, and it keeps the session.
    func askBeforeClose(_ question: CloseQuestion, then answer: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        (alert.messageText, alert.informativeText) = (question.title, question.message)
        for button in question.buttons { alert.addButton(withTitle: button) }
        present(alert) { answer($0 == .alertSecondButtonReturn) }
    }

    /// A sheet does not hold the main queue, so the output of the panes
    /// goes on behind it. A closed window has no sheet, so the alert
    /// stands alone then.
    private func present(_ alert: NSAlert, then finish: @escaping (NSApplication.ModalResponse) -> Void) {
        guard window.window.isVisible else { return finish(ModalAlert.runStandardModal(alert)) }
        alert.beginSheetModal(for: window.window, completionHandler: finish)
    }
}
