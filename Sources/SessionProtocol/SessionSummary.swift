import Foundation

/// What a client needs to know about a session to list it.
///
/// The facts after `createdAt` are optional, so a summary of an older
/// session process still decodes, and protocol version 1 does not change
/// (decision of 2026-10-19). A missing fact is unknown.
public struct SessionSummary: Codable, Equatable, Sendable {
    public var identifier: UUID
    /// The folder the session's program started in.
    public var folder: String
    /// The program and its arguments, as the user gave them. A session that
    /// runs the login shell holds the path of the shell.
    public var command: [String]
    public var size: SessionSize
    public var createdAt: Date
    /// The name that the user gave the session.
    public var name: String?
    /// The title that the program set with OSC 0 or OSC 2.
    public var title: String?
    /// The current folder of the program that reads the keys.
    public var currentFolder: String?
    /// The git branch of `currentFolder`, or the first seven characters of
    /// the commit when the repository has no branch checked out.
    public var branch: String?
    /// The name of the program that reads the keys, such as `zsh` or `claude`.
    public var foregroundProgram: String?
    /// Whether the program works: it writes output, or a command runs in
    /// the foreground of a shell with the terminal in line mode.
    public var isInProgress: Bool?
    public var lastOutputAt: Date?
    /// The time of the last input that a client typed or sent.
    public var lastInputAt: Date?
    public var alert: SessionAlert?
    /// The project that the session belongs to: the project whose folder
    /// holds the folder that the program started in, with its symbolic
    /// links resolved, and the deepest one when several do. `nil` means "No
    /// Project" (decision of 2026-11-10).
    public var projectIdentifier: UUID?

    /// The most Unicode scalars of a text that a program or a client chose,
    /// such as a title, a name or the text of an alert. A program could
    /// otherwise make each summary as large as a frame.
    public static let textLimit = 500

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

    /// The text without the characters of `isRemoved`, and with at most
    /// `textLimit` Unicode scalars. Text from a program is untrusted, and a
    /// list of sessions shows it on one line.
    public static func boundedText(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        var count = 0
        for scalar in text.unicodeScalars where !isRemoved(scalar) {
            guard count < textLimit else { break }
            kept.append(scalar)
            count += 1
        }
        return String(kept)
    }

    /// The control characters (C0, DEL and C1), the marks that change the
    /// direction of text, which could show the text in another order, and
    /// the line and paragraph separators. Other format characters stay, such
    /// as the joiner that emoji need.
    static func isRemoved(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F, 0x061C, 0x200E, 0x200F, 0x2028, 0x2029, 0x202A...0x202E, 0x2066...0x2069: true
        default: false
        }
    }
}
