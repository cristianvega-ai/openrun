import Foundation

/// What the second pane asks of its host. The host owns the sessions, so
/// the list shows a change only when the host gives it new content.
@MainActor
public protocol SessionsListDelegate: AnyObject {
    /// The user selected a row, or the selected row went away (`nil`). The
    /// third pane shows the content of the row.
    func sessionsList(_ list: SessionsListController, didSelect identifier: UUID?)
    /// The user pressed Return on a row. The keyboard focus goes to its content.
    func sessionsList(_ list: SessionsListController, didOpen identifier: UUID)
    /// The user wants a new thread or a new terminal.
    func sessionsList(_ list: SessionsListController, didRequest request: NewSessionRequest)
    /// The user wants to add or change the accounts of the agents.
    func sessionsListDidRequestAccounts(_ list: SessionsListController)
    /// The user gave a row a new name in place. The name is not empty.
    func sessionsList(_ list: SessionsListController, didRename identifier: UUID, to name: String)
    /// The user closed a row from its context menu.
    func sessionsList(_ list: SessionsListController, didClose identifier: UUID)
    /// The user dragged a row to `index` in the user's own order of the content.
    func sessionsList(_ list: SessionsListController, didMove identifier: UUID, toIndex index: Int)
    /// The user chose a filter or an order. The host keeps them for the next start.
    func sessionsList(_ list: SessionsListController, didChange filter: SessionsFilter, order: SessionsOrder)
}
