import Foundation

/// The chat panes of the threads that the user saw, by thread. A pane
/// stays attached, so a switch back to its row shows the chat at once.
/// Past the limit, the pane that the window showed longest ago closes,
/// as for the session panes.
@MainActor
final class ThreadPanes {
    static let limit = SessionPanes.limit
    private var panes: [UUID: ThreadPaneController] = [:]
    /// The threads in the order in which the window showed them last.
    private var recent: [UUID] = []

    /// The pane of a thread, which becomes the newest one. `make` gives a
    /// new pane at the first call, and the caller then attaches it.
    func pane(for thread: UUID, make: () -> ThreadPaneController) -> (pane: ThreadPaneController, isNew: Bool) {
        recent.removeAll { $0 == thread }
        recent.append(thread)
        if let pane = panes[thread] { return (pane, false) }
        let pane = make()
        panes[thread] = pane
        while recent.count > Self.limit { close(recent[0]) }
        return (pane, true)
    }

    func existing(_ thread: UUID) -> ThreadPaneController? {
        panes[thread]
    }

    var all: [ThreadPaneController] { Array(panes.values) }

    /// Detaches the pane of a thread. The thread goes on.
    func close(_ thread: UUID) {
        recent.removeAll { $0 == thread }
        panes.removeValue(forKey: thread)?.close()
    }

    func closeAll() {
        for thread in Array(panes.keys) { close(thread) }
    }
}
