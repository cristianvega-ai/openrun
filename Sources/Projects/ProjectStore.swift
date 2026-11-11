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

    /// Reads both files. A file that cannot be read is set aside, and the
    /// list starts without what it held.
    ///
    /// - Throws: `DataStorageError` when a file exists but the system cannot
    ///   read or move it. Do not save the list then, or the save replaces
    ///   projects that the load did not read.
    public func load() throws -> LoadedProjects {
        let projects = try dataFolder.read(ProjectsDocument.self)
        let folders = try dataFolder.read(ProjectFoldersDocument.self)
        var setAsidePaths: [String] = []
        if case .setAside(let path) = projects { setAsidePaths.append(path) }
        if case .setAside(let path) = folders { setAsidePaths.append(path) }
        let list = Self.merge(
            entries: projects.document?.projects ?? [],
            folders: folders.document?.folders ?? [:]
        )
        return LoadedProjects(list: list, setAsidePaths: setAsidePaths)
    }

    /// Joins each entry to its folder, in the order of the entries. A folder
    /// with no entry comes at the end with no name, in the order of the
    /// folders. So the projects stay when only `projects.json` is lost. A
    /// second entry for an identifier or a folder, a relative folder, and an
    /// entry with no folder are left out. A bad name is dropped, and the
    /// folder's name shows.
    static func merge(entries: [ProjectsDocument.Entry], folders: [String: String]) -> ProjectList {
        var folderOfIdentifier: [UUID: String] = [:]
        for (key, path) in folders {
            guard let identifier = UUID(uuidString: key), let folder = ProjectFolderPath.standardized(path) else { continue }
            folderOfIdentifier[identifier] = folder
        }
        let listed = Set(entries.map(\.identifier))
        let orphans = folderOfIdentifier
            .filter { !listed.contains($0.key) }
            .sorted { ($0.value, $0.key.uuidString) < ($1.value, $1.key.uuidString) }
            .map { ProjectsDocument.Entry(identifier: $0.key, name: nil) }
        var projects: [Project] = []
        var identifiers = Set<UUID>()
        var usedFolders = Set<String>()
        for entry in entries + orphans where projects.count < ProjectList.countLimit {
            guard let folder = folderOfIdentifier[entry.identifier],
                  identifiers.insert(entry.identifier).inserted,
                  usedFolders.insert(folder).inserted else { continue }
            let name = (try? Project.validName(entry.name)) ?? nil
            projects.append(Project(identifier: entry.identifier, folder: folder, name: name))
        }
        return ProjectList(checked: projects)
    }
}
