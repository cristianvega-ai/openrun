import AppKit
import ListContent
import SessionsList

/// What the user does in the second pane.
extension Workspace: SessionsListDelegate {
    func sessionsList(_ list: SessionsListController, didSelect identifier: UUID?) {
        // A row that leaves the list, such as through the filter, keeps
        // its place in the third pane, so `nil` changes nothing.
        guard !isRefreshing, let identifier else { return }
        select(row: identifier)
    }

    func sessionsList(_ list: SessionsListController, didOpen identifier: UUID) {
        window.focusContent()
    }

    func sessionsList(_ list: SessionsListController, didRequest request: NewSessionRequest) {
        switch request {
        // A thread with an agent is a chat, which a later version brings.
        // Until then the agent runs in a terminal.
        case .thread(let name), .terminal(let name?): newSession(commandNamed: name)
        case .terminal(nil): newSession()
        }
    }

    func sessionsList(_ list: SessionsListController, didRename identifier: UUID, to name: String) {
        // The name belongs to the first session of the row, so `openrun list` shows it too.
        guard let session = layout.row(identifier)?.pane.sessions.first else { return }
        perform("The session could not get its name") { try $0.rename(session: session, to: name) }
    }

    func sessionsList(_ list: SessionsListController, didClose identifier: UUID) {
        closeRow(identifier)
    }

    func sessionsList(_ list: SessionsListController, didMove identifier: UUID, toIndex index: Int) {
        let content = ListContent(overview: connection.overview, layout: layout, inView: nil, home: home)
        layout.moveRow(identifier, toIndex: index, among: content.rows(of: window.projectsList.selection).map(\.identifier))
        refresh()
    }

    func sessionsList(_ list: SessionsListController, didChange filter: SessionsFilter, order: SessionsOrder) {
        (layout.filter, layout.order) = (filter.rawValue, order.rawValue)
        refresh()
    }

    /// Selects a row for the user. An alert ends when the user selects
    /// its session (decision of 2026-11-10).
    func select(row identifier: UUID) {
        layout.selectedRow = identifier
        for session in layout.row(identifier)?.pane.sessions ?? [] { clearAlert(of: session) }
        refresh()
    }

    /// Selects the row after or before the selected one in the list, and
    /// goes around at its ends.
    func moveSelection(by step: Int) {
        let rows = window.sessionsList.shownIdentifiers
        guard !rows.isEmpty else { return }
        let current = layout.selectedRow.flatMap(rows.firstIndex(of:))
        select(row: rows[current.map { ($0 + step + rows.count) % rows.count } ?? (step > 0 ? 0 : rows.count - 1)])
    }
}
