import Foundation

/// A change to the project list was refused. Nothing changed.
public enum ProjectListError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A relative path came with no current folder to start from.
    case relativeFolder(path: String)
    case folderDoesNotExist(path: String)
    case notAFolder(path: String)
    /// Another project already has this folder.
    case duplicateFolder(path: String, project: UUID)
    case unknownProject(UUID)
    /// The name is too long or holds a control character.
    case invalidName
    /// A move named a place outside the list.
    case placeOutOfRange(place: Int, count: Int)
    case tooManyProjects(limit: Int)

    public var description: String {
        switch self {
        case .relativeFolder(let path): "The folder \(path) is relative, and no current folder was given."
        case .folderDoesNotExist(let path): "The folder \(path) does not exist."
        case .notAFolder(let path): "\(path) is not a folder."
        case .duplicateFolder(let path, _): "The folder \(path) is already a project."
        case .unknownProject(let identifier): "No project has the identifier \(identifier.uuidString)."
        case .invalidName: "A project name has at most \(Project.nameLengthLimit) characters and no control characters."
        case .placeOutOfRange(let place, let count): "The place \(place) is outside the list of \(count) projects."
        case .tooManyProjects(let limit): "OpenRun keeps at most \(limit) projects."
        }
    }
}
