import AppKit

/// Shows a question of the launch agent setup, which runs on a thread of its
/// own, and waits for the answer.
enum ModalAlert {
    /// Runs the modal loop of an alert. Tests pass their own, because a test
    /// cannot answer a real alert.
    typealias RunModal = @MainActor (NSAlert) -> NSApplication.ModalResponse

    /// Returns whether the user chose the first button. The calling thread
    /// waits, so it must not be the main thread.
    nonisolated static func ask(_ question: LaunchAgentQuestion, runModal: @escaping RunModal = runStandardModal) -> Bool {
        precondition(!Thread.isMainThread, "The main thread would wait for itself.")
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { response(to: question, runModal: runModal) == .alertFirstButtonReturn }
        }
    }

    @MainActor static func runStandardModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }

    @MainActor private static func response(to question: LaunchAgentQuestion, runModal: RunModal) -> NSApplication.ModalResponse {
        let words = question.words
        let alert = NSAlert()
        alert.messageText = words.title
        alert.informativeText = words.message
        for button in words.buttons { alert.addButton(withTitle: button) }
        return runModal(alert)
    }
}
