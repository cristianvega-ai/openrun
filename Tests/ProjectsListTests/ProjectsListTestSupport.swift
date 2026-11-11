import AppKit
@testable import ProjectsList

/// Keeps what the first pane reports.
@MainActor
final class RecordingProjectsHost: ProjectsListDelegate {
    var selections: [ProjectsListEntry] = []
    var newProjectRequests = 0
    var removals: [UUID] = []
    var renames: [(UUID, String)] = []

    func projectsList(_ list: ProjectsListController, didSelect entry: ProjectsListEntry) { selections.append(entry) }
    func projectsListDidRequestNewProject(_ list: ProjectsListController) { newProjectRequests += 1 }
    func projectsList(_ list: ProjectsListController, didRemoveProject identifier: UUID) { removals.append(identifier) }
    func projectsList(_ list: ProjectsListController, didRenameProject identifier: UUID, to name: String) { renames.append((identifier, name)) }
}

/// A first pane in a window, with three projects.
@MainActor
func makeProjectsList() -> (ProjectsListController, RecordingProjectsHost, NSWindow, [UUID]) {
    _ = NSApplication.shared
    let list = ProjectsListController(), host = RecordingProjectsHost()
    list.delegate = host
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = list.view
    let identifiers = [UUID(), UUID(), UUID()]
    list.show(ProjectsListContent(projects: zip(identifiers, ["openrun", "website", "notes"]).map {
        ProjectDisplay(identifier: $0, name: $1, folder: "/Users/user/Projects/\($1)")
    }))
    window.layoutIfNeeded()
    return (list, host, window, identifiers)
}

extension ProjectsListController {
    func cell(at row: Int) -> ProjectCellView? {
        table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ProjectCellView
    }
}
