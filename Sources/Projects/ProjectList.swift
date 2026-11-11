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

    private func index(of identifier: UUID) throws -> Int {
        guard let index = projects.firstIndex(where: { $0.identifier == identifier }) else {
            throw ProjectListError.unknownProject(identifier)
        }
        return index
    }
}
