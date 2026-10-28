import AppKit
import SessionProtocol

/// A list of sessions in an AppKit question. A session is named by its folder
/// and identifier, so two sessions in the same folder remain distinct.
@MainActor
enum SessionListPanel {
    static func choose(
        _ summaries: [SessionSummary], in window: NSWindow?,
        present: @MainActor (NSAlert, NSWindow?) async -> NSApplication.ModalResponse = show
    ) async -> UUID? {
        let alert = NSAlert()
        guard !summaries.isEmpty else {
            alert.messageText = "No running sessions"
            alert.informativeText = "Start a new session to open a window."
            alert.addButton(withTitle: "OK")
            _ = await present(alert, window)
            return nil
        }
        alert.messageText = "Attach to a Session"
        alert.informativeText = "Choose a running session."
        let choices = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 480, height: 28), pullsDown: false)
        for summary in summaries { choices.addItem(withTitle: "\(summary.folder) — \(summary.identifierText)") }
        alert.accessoryView = choices
        alert.addButton(withTitle: "Attach")
        alert.addButton(withTitle: "Cancel")
        guard await present(alert, window) == .alertFirstButtonReturn,
              summaries.indices.contains(choices.indexOfSelectedItem) else { return nil }
        return summaries[choices.indexOfSelectedItem].identifier
    }

    static func showFailure(_ detail: String, in window: NSWindow?) async {
        let alert = NSAlert()
        alert.messageText = "The session list is not available"
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        _ = await show(alert, in: window)
    }

    private static func show(_ alert: NSAlert, in window: NSWindow?) async -> NSApplication.ModalResponse {
        guard let window, window.isVisible else { return alert.runModal() }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
    }
}
