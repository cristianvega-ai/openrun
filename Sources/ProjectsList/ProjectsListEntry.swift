import Foundation

/// One entry of the first pane: every session, the rows that need the user
/// from every project, one project, or the sessions outside every project
/// (decisions of 2026-11-10).
public enum ProjectsListEntry: Hashable, Sendable {
    case allSessions
    case needsYou
    case project(UUID)
    case noProject
}
