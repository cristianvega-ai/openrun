import DataStorage
import Foundation

/// Loads and saves the project list in the data folder.
///
/// The list takes two files: the names and the order can sync, and the
/// folders stay on this Mac. A save writes the folders first. So a crash
/// between the two writes leaves either a folder with no entry, which the
/// next load adds back at the end, or an entry with no folder, which the
/// next load leaves out. Either way, the last change completes.
public struct ProjectStore: Sendable {
    public let dataFolder: DataFolder

    public init(dataFolder: DataFolder = .default) {
        self.dataFolder = dataFolder
    }

    /// Makes the data folder when it does not exist, and writes both files.
    public func save(_ list: ProjectList) throws {
        try dataFolder.create()
        var folders: [String: String] = [:]
        for project in list.projects {
            folders[project.identifier.uuidString] = project.folder
        }
        try dataFolder.write(ProjectFoldersDocument(folders: folders))
        try dataFolder.write(ProjectsDocument(projects: list.projects.map {
            ProjectsDocument.Entry(identifier: $0.identifier, name: $0.name)
        }))
    }
}
