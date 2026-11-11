import AppKit
import SessionsList

/// What the user does in the second pane.
extension Workspace: SessionsListDelegate {
    func sessionsList(_ list: SessionsListController, didSelect identifier: UUID?) {
        // A row that leaves the list, such as through the filter, keeps
        // its place in the third pane, so `nil` changes nothing.
        guard !isRefreshing, let identifier else { return }
        layout.selectedRow = identifier
        refresh()
    }

    func sessionsList(_ list: SessionsListController, didOpen identifier: UUID) {
        window.focusContent()
    }

    func sessionsList(_ list: SessionsListController, didRequest request: NewSessionRequest) {}
    func sessionsList(_ list: SessionsListController, didRename identifier: UUID, to name: String) {}
    func sessionsList(_ list: SessionsListController, didClose identifier: UUID) {}
    func sessionsList(_ list: SessionsListController, didMove identifier: UUID, toIndex index: Int) {}
    func sessionsList(_ list: SessionsListController, didChange filter: SessionsFilter, order: SessionsOrder) {}
}
