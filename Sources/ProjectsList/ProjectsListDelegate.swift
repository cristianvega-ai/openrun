import Foundation

/// What the first pane asks of its host. The host owns the projects, so the
/// list shows a change only when the host gives it new content.
@MainActor
public protocol ProjectsListDelegate: AnyObject {
    /// The user selected an entry. The second pane shows its sessions.
    func projectsList(_ list: ProjectsListController, didSelect entry: ProjectsListEntry)
}
