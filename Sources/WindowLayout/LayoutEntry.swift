import Foundation

/// The entry of the first pane that the user selected: every session, the
/// rows that need the user, or one project (decisions of 2026-11-10).
public enum LayoutEntry: Hashable, Sendable {
    case allSessions
    case needsYou
    case project(UUID)
}

/// The file holds one text: a fixed word, or the identifier of a project.
extension LayoutEntry: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        switch text {
        case "needs-you": self = .needsYou
        // A word of another build means every session, the first entry. An
        // earlier build wrote `no-project` for the sessions outside every project.
        default: self = UUID(uuidString: text).map(LayoutEntry.project) ?? .allSessions
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .allSessions: try value.encode("all-sessions")
        case .needsYou: try value.encode("needs-you")
        case .project(let identifier): try value.encode(identifier.uuidString)
        }
    }
}
