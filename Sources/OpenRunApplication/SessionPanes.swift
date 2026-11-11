import Foundation
import SessionPane

/// The session panes of the main window, by session.
///
/// The pane of a row that the user looked at stays attached, so a switch
/// back to the row is instant. A pane outside a window sends no size and
/// draws nothing, so it does not hold the grid of its session.
@MainActor
final class SessionPanes {
    /// The most panes that stay attached. Each one holds a connection and
    /// a terminal with its scrollback, and reads the output of its
    /// session. Eight cover the rows that a user moves between, and they
    /// leave most of the 64 clients of the session process free.
    static let limit = 8
    private var panes: [UUID: SessionPaneController] = [:]
    /// The sessions in the order in which the window showed them last,
    /// the newest at the end.
    private var recent: [UUID] = []
    private let makePane: (UUID) -> SessionPaneController

    init(makePane: @escaping (UUID) -> SessionPaneController) {
        self.makePane = makePane
    }

    /// The pane of a session, which becomes the newest one. The first
    /// call makes it, and the caller then attaches it. Past the limit,
    /// the pane that the window showed longest ago closes.
    func pane(for session: UUID) -> (pane: SessionPaneController, isNew: Bool) {
        recent.removeAll { $0 == session }
        recent.append(session)
        if let pane = panes[session] { return (pane, false) }
        let pane = makePane(session)
        panes[session] = pane
        while recent.count > Self.limit { close(recent[0]) }
        return (pane, true)
    }

    func existing(_ session: UUID) -> SessionPaneController? {
        panes[session]
    }

    func session(of pane: SessionPaneController) -> UUID? {
        panes.first { $0.value === pane }?.key
    }

    var all: [SessionPaneController] { Array(panes.values) }

    /// Detaches the pane of a session. The session goes on.
    func close(_ session: UUID) {
        recent.removeAll { $0 == session }
        panes.removeValue(forKey: session)?.close()
    }

    func closeAll() {
        for session in Array(panes.keys) { close(session) }
    }
}
