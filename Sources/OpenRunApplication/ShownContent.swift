import Foundation

/// What the third pane shows now.
enum ShownContent: Equatable {
    /// The empty state of the pane.
    case nothing
    /// The pane of a session.
    case session(UUID)
    /// The chat of an agent thread.
    case thread(UUID)
    case notice(PaneNotice)
}
