import Foundation

/// What a client needs to know about a session to list it.
public struct SessionSummary: Codable, Equatable, Sendable {
    public var identifier: UUID
    /// The folder the session's program started in.
    public var folder: String
    /// The program and its arguments, as the user gave them. A session that
    /// runs the login shell holds the path of the shell.
    public var command: [String]
    public var size: SessionSize
    public var createdAt: Date

    public init(identifier: UUID, folder: String, command: [String], size: SessionSize, createdAt: Date) {
        self.identifier = identifier
        self.folder = folder
        self.command = command
        self.size = size
        self.createdAt = createdAt
    }

    /// The identifier as people see it and as programs in the session read it:
    /// lowercase, so a prefix typed in either case matches.
    public var identifierText: String {
        Self.text(for: identifier)
    }

    public static func text(for identifier: UUID) -> String {
        identifier.uuidString.lowercased()
    }
}
