import AlertNotifications
import AppKit
import ListContent
import MainWindow
import SessionOverview
import SessionProtocol

/// The agent threads in the main window: their chats in the third pane,
/// and what the user does with a thread (proposal 1 of 2026-11-10).
extension Workspace {
    /// Shows the chat of a thread.
    func showChat(of thread: UUID) {
        guard let summary = connection.overview.thread(thread) else { return window.showContent(nil) }
        let pane = chatPane(of: summary)
        window.showContent(PaneContent(
            viewController: pane.chat, title: pane.chat.facts.title, minimumSize: pane.chat.minimumSize, topRowItems: pane.chat.topRowItems))
    }

    /// The chat pane of a thread. A new pane attaches to its thread.
    func chatPane(of summary: ThreadSummary) -> ThreadPaneController {
        let thread = summary.identifier
        let (pane, isNew) = threadPanes.pane(for: thread) { ThreadPaneController(summary: summary, socket: socket, home: home) }
        if isNew {
            pane.failed = { [weak self] in self?.showFailure("The thread could not do that", $0) }
            pane.openInTerminal = { [weak self] in self?.openThreadInTerminal(thread) }
            pane.returnFromTerminal = { [weak self] in self?.returnThreadFromTerminal(thread) }
            pane.attach()
        }
        return pane
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

    /// The agents of a new thread, as the session process names them.
    /// The first one is the agent of File > New Thread.
    static let threadAgents = ["claude-code", "codex"]

    /// Makes a thread with an agent in the folder of the selected
    /// project, or in the home folder. Its row takes the selection and
    /// the focus when the feed brings it.
    func newThread(agent: String = Workspace.threadAgents[0]) {
        let folder = selectedProjectFolder ?? home
        requests.perform({ try $0.createThread(agent: agent, folder: folder).identifier }, then: { [weak self] result in
            switch result {
            case .success(let thread): self?.select(newSession: thread)
            case .failure(let failure): self?.showFailure("The thread could not start", failure.message)
            }
        })
    }

    /// Closes a thread after a question. Its record goes away, and the
    /// conversation stays in the history of the agent.
    func closeThread(_ thread: UUID) {
        let title = connection.overview.thread(thread).map(ThreadRowFacts.title(of:)) ?? ThreadRowFacts.untitled
        confirmCloseOfThread(title) { [weak self] agreed in
            if agreed { self?.perform("The thread could not close") { try $0.closeThread(thread) } }
        }
    }

    /// Asks before the close of a thread. The first button keeps it.
    func askBeforeCloseOfThread(_ title: String, then answer: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Close the thread “\(title)”?"
        alert.informativeText = "OpenRun ends its agent and removes it from the list. The conversation stays in the history of the agent."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Close Thread")
        guard window.window.isVisible else { return answer(ModalAlert.runStandardModal(alert) == .alertSecondButtonReturn) }
        alert.beginSheetModal(for: window.window) { answer($0 == .alertSecondButtonReturn) }
    }
}
