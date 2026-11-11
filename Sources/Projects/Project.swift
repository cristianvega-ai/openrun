import Foundation
import UntrustedText

/// A folder that the user added, usually a repository. New sessions in the
/// project start in its folder.
public struct Project: Hashable, Sendable {
    /// Stays the same for the life of the project, also when the user
    /// renames it, so a later sync can match it on another Mac.
    public let identifier: UUID
    /// Absolute and standard, with its symbolic links resolved.
    public internal(set) var folder: String
    /// The name that the user gave, or `nil` to show the folder's name.
    public internal(set) var name: String?

    /// A name longer than this does not fit in the first pane.
    public static let nameLengthLimit = 100

    init(identifier: UUID, folder: String, name: String?) {
        self.identifier = identifier
        self.folder = folder
        self.name = name
    }

    /// The name, or the last part of the folder.
    public var shownName: String {
        if let name { return name }
        return folder == "/" ? "/" : (folder as NSString).lastPathComponent
    }

    /// Removes the spaces at both ends, and gives `nil` for a name with no
    /// other characters, so the folder's name shows again.
    ///
    /// - Throws: `ProjectListError.invalidName` for a name that is too long
    ///   or that `PlainName` refuses, because the name shows in the app's
    ///   list and in a terminal.
    static func validName(_ name: String?) throws -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard PlainName.isValid(trimmed, lengthLimit: nameLengthLimit) else { throw ProjectListError.invalidName }
        return trimmed
    }
}
