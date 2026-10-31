import AppKit
import SessionProtocol

/// A list of sessions in an AppKit question. A session is named by its folder
/// and identifier, so two sessions in the same folder remain distinct.
@MainActor
enum SessionListPanel {
    /// Runs the modal loop of an alert. Tests pass their own, because a test
    /// cannot answer a real alert.
    typealias RunModal = @MainActor (NSAlert) -> NSApplication.ModalResponse

    static func choose(
        _ summaries: [SessionSummary], in window: NSWindow?,
        runModal: @escaping RunModal = { $0.runModal() }
    ) async -> UUID? {
        let alert = NSAlert()
        guard !summaries.isEmpty else {
            alert.messageText = "No running sessions"
            alert.informativeText = "Start a new session to open a window."
            alert.addButton(withTitle: "OK")
            _ = await show(alert, in: window, runModal: runModal)
            return nil
        }
        alert.messageText = "Attach to a Session"
        alert.informativeText = "Choose a running session."
        let choices = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 480, height: 28), pullsDown: false)
        for summary in summaries { choices.addItem(withTitle: "\(summary.folder) — \(summary.identifierText)") }
        alert.accessoryView = choices
        alert.addButton(withTitle: "Attach")
        alert.addButton(withTitle: "Cancel")
        guard await show(alert, in: window, runModal: runModal) == .alertFirstButtonReturn,
              summaries.indices.contains(choices.indexOfSelectedItem) else { return nil }
        return summaries[choices.indexOfSelectedItem].identifier
    }

    static func showFailure(_ detail: String, in window: NSWindow?, runModal: @escaping RunModal = { $0.runModal() }) async {
        let alert = NSAlert()
        alert.messageText = "The session list is not available"
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        _ = await show(alert, in: window, runModal: runModal)
    }

    private static func show(_ alert: NSAlert, in window: NSWindow?, runModal: @escaping RunModal) async -> NSApplication.ModalResponse {
        guard let window, window.isVisible else {
            // This code runs in a main actor job, which is a block of the main
            // dispatch queue. A modal loop inside such a block holds the queue
            // until the alert closes, so the blocks that deliver the output of
            // attached windows wait, and those windows lose their connection.
            // A run loop block is no block of that queue.
            return await withCheckedContinuation { continuation in
                RunLoop.main.perform(inModes: [.common]) {
                    continuation.resume(returning: MainActor.assumeIsolated { runModal(alert) })
                }
            }
        }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
    }
}
