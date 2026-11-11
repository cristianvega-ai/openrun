import AlertNotifications
import AppKit
import ListContent
import MainWindow
import SessionOverview
import SessionProtocol

/// The agent threads in the main window: their chats in the third pane,
/// and what the user does with a thread (proposal 1 of 2026-11-10).
extension Workspace {
    /// Shows the chat of a thread. A new pane attaches to its thread.
    func showChat(of thread: UUID) {
        guard let summary = connection.overview.thread(thread) else { return window.showContent(nil) }
        let (pane, isNew) = threadPanes.pane(for: thread) { ThreadPaneController(summary: summary, socket: socket, home: home) }
        if isNew {
            pane.failed = { [weak self] in self?.showFailure("The thread could not do that", $0) }
            pane.attach()
        }
        window.showContent(PaneContent(viewController: pane.chat, title: pane.chat.facts.title, minimumSize: pane.chat.minimumSize))
    }

    /// A batch of changes came. The chat of a thread that closed goes
    /// away, and each open chat takes the new facts of its thread.
    func threadsChanged(from previous: SessionOverview) {
        let overview = connection.overview
        for thread in previous.threads where overview.thread(thread.identifier) == nil {
            threadPanes.close(thread.identifier)
            if shownThread == thread.identifier { shownIsStale = true }
        }
        for pane in threadPanes.all {
            if let summary = overview.thread(pane.thread) { pane.update(summary, home: home) }
        }
        // An agent that starts to wait for an answer of the user gives a
        // notification, unless the user looks at its chat.
        for thread in overview.threads where thread.state != previous.thread(thread.identifier)?.state {
            if thread.state == "needsUser", thread.identifier != sessionInView, settings.showsNotifications {
                let body = "\(ThreadRowFacts.agentName(thread.agent)) waits for your answer."
                notifier.post(AlertNotification(identifier: thread.identifierText, title: ThreadRowFacts.title(of: thread), body: body))
            } else if previous.thread(thread.identifier)?.state == "needsUser" {
                notifier.remove(identifier: thread.identifierText)
            }
        }
    }
}
