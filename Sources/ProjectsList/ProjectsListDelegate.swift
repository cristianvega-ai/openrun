import Foundation

/// What the first pane asks of its host. The host owns the projects, so the
/// list shows a change only when the host gives it new content.
@MainActor
public protocol ProjectsListDelegate: AnyObject {
    /// The user selected an entry. The second pane shows its sessions.
    func projectsList(_ list: ProjectsListController, didSelect entry: ProjectsListEntry)
    /// The user wants a new project. The host asks for a folder.
    func projectsListDidRequestNewProject(_ list: ProjectsListController)
    /// The user dropped folders from Finder on the pane.
    func projectsList(_ list: ProjectsListController, didRequestProjectsAt folders: [URL])
    func projectsList(_ list: ProjectsListController, didRemoveProject identifier: UUID)
    /// The user gave a project a new name in place. The name is not empty.
    func projectsList(_ list: ProjectsListController, didRenameProject identifier: UUID, to name: String)
    /// The user dragged a project to `index` among the projects.
    func projectsList(_ list: ProjectsListController, didMoveProject identifier: UUID, toIndex index: Int)
}
