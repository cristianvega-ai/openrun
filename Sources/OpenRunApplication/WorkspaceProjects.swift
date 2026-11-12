import AppKit
import ListContent
import ProjectsList

/// What the user does in the first pane. The session process owns the
/// projects, so each change goes there, and the list shows the change
/// when the feed brings it.
extension Workspace: ProjectsListDelegate {
    func projectsList(_ list: ProjectsListController, didSelect entry: ProjectsListEntry) {
        // The refresh reads the entry from the list and keeps it.
        if !isRefreshing { refresh() }
    }

    func projectsListDidRequestNewProject(_ list: ProjectsListController) {
        chooseProjectFolders { [weak self] folders in self?.addProjects(at: folders) }
    }

    func projectsList(_ list: ProjectsListController, didRequestProjectsAt folders: [URL]) {
        addProjects(at: folders)
    }

    func projectsList(_ list: ProjectsListController, didRemoveProject identifier: UUID) {
        // The sessions of the project stay, and show under "All Projects".
        perform("The project could not be removed") { try $0.removeProject(identifier) }
    }

    func projectsList(_ list: ProjectsListController, didRenameProject identifier: UUID, to name: String) {
        perform("The project could not get its name") { try $0.renameProject(identifier, to: name) }
    }

    func projectsList(_ list: ProjectsListController, didMoveProject identifier: UUID, toIndex index: Int) {
        perform("The project could not move") { try $0.moveProject(identifier, to: index) }
    }

    /// Adds each folder as a project. The last one takes the selection
    /// when the feed brings it.
    func addProjects(at folders: [URL]) {
        for folder in folders {
            let path = folder.path
            requests.perform({ try $0.addProject(folder: path, name: nil, currentFolder: nil).identifier }, then: { [weak self] result in
                switch result {
                case .success(let identifier):
                    self?.projectToSelect = identifier
                    self?.refresh()
                case .failure(let failure):
                    self?.showFailure("The project could not be added", failure.message)
                }
            })
        }
    }

    /// Asks for the folders of new projects in a sheet on the window.
    func chooseFoldersInPanel(then add: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        (panel.canChooseFiles, panel.canChooseDirectories, panel.allowsMultipleSelection) = (false, true, true)
        (panel.prompt, panel.message) = ("Add Project", "Choose the folder of a project, such as a repository.")
        panel.beginSheetModal(for: window.window) { response in
            if response == .OK { add(panel.urls) }
        }
    }
}
