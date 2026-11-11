import DataStorage
import Foundation

/// The part of the projects that can sync: the identifiers, the names and
/// the order. The folders stay on this Mac in `ProjectFoldersDocument`.
struct ProjectsDocument: DataDocument {
    static let file = DataFile.projects
    static let format = 1

    struct Entry: Codable, Sendable {
        var identifier: UUID
        var name: String?
    }

    var projects: [Entry]
}
