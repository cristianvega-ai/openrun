import Foundation

/// One entry of the first pane: every session, the rows that need the user
/// from every project, or one project (decisions of 2026-11-10). A session
/// outside every project shows under every session only (2026-11-12).
public enum ProjectsListEntry: Hashable, Sendable {
    case allSessions
    case needsYou
    case project(UUID)
}
