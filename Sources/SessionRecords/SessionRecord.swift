import Foundation

/// What OpenRun keeps of a terminal session, so that the session comes
/// back after a restart of the session process, such as after a restart
/// of the Mac (decision of 2026-10-15). The record holds no environment
/// and no output of the session.
public struct SessionRecord: Codable, Equatable, Sendable {
    public var identifier: UUID
    /// The folder in which the session comes back: the newest current
    /// folder of its program.
    public var folder: String
    /// The name that the user gave the session.
    public var name: String?
    public var columns: Int
    public var rows: Int
    public var createdAt: Date

    public init(identifier: UUID, folder: String, name: String? = nil, columns: Int, rows: Int, createdAt: Date) {
        (self.identifier, self.folder, self.name) = (identifier, folder, name)
        (self.columns, self.rows, self.createdAt) = (columns, rows, createdAt)
    }

    static let folderLengthLimit = 4_096
    static let nameLengthLimit = 500

    /// Whether the file can hold the record: a full path, a name of a
    /// sensible length, and a size that a terminal can have.
    var isValid: Bool {
        folder.hasPrefix("/") && folder.utf8.count <= Self.folderLengthLimit && (name?.unicodeScalars.count ?? 0) <= Self.nameLengthLimit
            && (1...10_000).contains(columns) && (1...10_000).contains(rows)
    }
}
