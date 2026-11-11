import ProjectsList
import WindowLayout

/// The first pane and the kept layout name the same entries, each with a
/// type of its own module, so that neither module depends on the other.
extension ProjectsListEntry {
    public init(_ entry: LayoutEntry) {
        switch entry {
        case .allSessions: self = .allSessions
        case .needsYou: self = .needsYou
        case .project(let identifier): self = .project(identifier)
        case .noProject: self = .noProject
        }
    }

    public var layoutEntry: LayoutEntry {
        switch self {
        case .allSessions: .allSessions
        case .needsYou: .needsYou
        case .project(let identifier): .project(identifier)
        case .noProject: .noProject
        }
    }
}
