import Foundation

/// A project as the session process tells its clients: a folder that the
/// user added, usually a repository (decisions of 2026-10-15 and 2026-11-10).
///
/// The protocol keeps its own plain type, so a client needs no other module
/// of OpenRun to read it.
public struct ProjectSummary: Codable, Equatable, Sendable {
    /// Stays the same for the life of the project, also after a rename.
    public var identifier: UUID
    /// The name that the user gave, or `nil`: a client then shows the last
    /// name of the folder.
    public var name: String?
    /// Absolute, standard, and with its symbolic links resolved. `nil` when
    /// this Mac does not know the folder of the project. Such a project
    /// holds no session, and a client can show it so that the user removes it.
    public var folder: String?

    public init(identifier: UUID, name: String?, folder: String?) {
        self.identifier = identifier
        self.name = name
        self.folder = folder
    }
}
