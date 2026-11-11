import Foundation
import SessionConnection
import SessionProtocol

/// `openrun project add`, `remove` and `rename`.
struct ProjectChangeCommand {
    enum Change: Equatable {
        case add(folder: String, name: String?)
        /// The project is an identifier start or a folder.
        case remove(project: String)
        /// A nil name removes the name.
        case rename(project: String, name: String?)
    }

    var change: Change

    /// - Returns: The identifier of a new project and a new line, or nothing.
    func run(location: SocketLocation) throws -> String {
        let client = try SessionClient(location: location)
        // The session process runs in another folder than this command.
        let currentFolder = FileManager.default.currentDirectoryPath
        let homeFolder = FileManager.default.homeDirectoryForCurrentUser.path
        func project(_ typed: String) throws -> UUID {
            try ProjectMatch.find(typed, in: client.projects(), currentFolder: currentFolder, homeFolder: homeFolder).identifier
        }
        switch change {
        case .add(let folder, let name):
            return try client.addProject(folder: folder, name: name, currentFolder: currentFolder).identifierText + "\n"
        case .remove(let typed):
            try client.removeProject(project(typed))
        case .rename(let typed, let name):
            try client.renameProject(project(typed), to: name)
        }
        return ""
    }
}
