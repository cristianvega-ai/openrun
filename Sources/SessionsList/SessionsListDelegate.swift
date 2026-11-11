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
}
