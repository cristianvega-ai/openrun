import Foundation

/// The projects in the order that the user chose.
///
/// Each operation checks its input first and changes nothing when it
/// throws, so a refused request leaves the list as it was.
public struct ProjectList: Hashable, Sendable {
    public private(set) var projects: [Project]

    /// More projects than this do not fit in the first pane, and a program
    /// in a loop must not grow the file without end.
    public static let countLimit = 1000

    public init() {
        projects = []
    }

    /// The list as a file held it. The store checks each project first.
    init(checked projects: [Project]) {
        self.projects = projects
    }

    public func project(identifier: UUID) -> Project? {
        projects.first { $0.identifier == identifier }
    }

    /// The project of a session that started in `folder`: the project whose
    /// folder holds it, and the deepest one when several do. `nil` means
    /// that the session shows under "No Project".
    ///
    /// Names compare whole, so `/work/app` does not hold
    /// `/work/application`. The folder should be the real path that the
    /// system gives, or a path from `ProjectFolderPath.resolve`, because
    /// this reads no file and does not follow symbolic links. A relative
    /// folder belongs to no project.
    public func project(holding folder: String) -> Project? {
        guard folder.hasPrefix("/") else { return nil }
        let target = ProjectFolderPath.components(of: folder)
        var best: (project: Project, depth: Int)?
        for project in projects {
            let candidate = ProjectFolderPath.components(of: project.folder)
            guard ProjectFolderPath.holds(candidate, target), candidate.count > best?.depth ?? -1 else { continue }
            best = (project, candidate.count)
        }
        return best?.project
    }

    /// Adds a folder at the end of the list.
    ///
    /// The folder must exist and be a folder now. A folder that the user
    /// removes later stays in the list, and a session started there fails
    /// as it would in a shell.
    ///
    /// - Parameters:
    ///   - folder: as the user typed it. See `ProjectFolderPath.resolve`.
    ///   - currentFolder: the folder of the program that asks, for a
    ///     relative path.
    /// - Throws: `ProjectListError`.
    @discardableResult
    public mutating func add(
        folder: String,
        name: String? = nil,
        homeFolder: String = NSHomeDirectory(),
        currentFolder: String? = nil
    ) throws -> Project {
        guard projects.count < Self.countLimit else { throw ProjectListError.tooManyProjects(limit: Self.countLimit) }
        let resolved = try ProjectFolderPath.resolve(folder, homeFolder: homeFolder, currentFolder: currentFolder)
        if let existing = projects.first(where: { $0.folder == resolved }) {
            throw ProjectListError.duplicateFolder(path: resolved, project: existing.identifier)
        }
        let project = Project(identifier: UUID(), folder: resolved, name: try Project.validName(name))
        projects.append(project)
        return project
    }

    /// Removes a project. Its sessions keep running and show under
    /// "No Project".
    public mutating func remove(identifier: UUID) throws {
        projects.remove(at: try index(of: identifier))
    }

    /// Gives a project a name, or takes its name away with `nil` or an
    /// empty name, so the folder's name shows again.
    public mutating func rename(identifier: UUID, to name: String?) throws {
        let index = try index(of: identifier)
        projects[index].name = try Project.validName(name)
    }

    /// Moves a project so that it has the place `place` in the new order.
    /// The first place is 0, and the last is `projects.count - 1`.
    public mutating func move(identifier: UUID, to place: Int) throws {
        let index = try index(of: identifier)
        guard projects.indices.contains(place) else {
            throw ProjectListError.placeOutOfRange(place: place, count: projects.count)
        }
        projects.insert(projects.remove(at: index), at: place)
    }

    private func index(of identifier: UUID) throws -> Int {
        guard let index = projects.firstIndex(where: { $0.identifier == identifier }) else {
            throw ProjectListError.unknownProject(identifier)
        }
        return index
    }
}
