import Foundation

/// What the first pane asks of its host. The host owns the projects, so the
/// list shows a change only when the host gives it new content.
@MainActor
public protocol ProjectsListDelegate: AnyObject {
    /// The user selected an entry. The second pane shows its sessions.
    func projectsList(_ list: ProjectsListController, didSelect entry: ProjectsListEntry)
    /// The user wants a new project. The host asks for a folder.
    func projectsListDidRequestNewProject(_ list: ProjectsListController)
    func projectsList(_ list: ProjectsListController, didRemoveProject identifier: UUID)
    /// The user gave a project a new name in place. The name is not empty.
    func projectsList(_ list: ProjectsListController, didRenameProject identifier: UUID, to name: String)
}
