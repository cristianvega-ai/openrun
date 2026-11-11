import Foundation

/// What the third pane shows now.
enum ShownContent: Equatable {
    /// The empty state of the pane.
    case nothing
    /// The pane of a session.
    case session(UUID)
    case notice(PaneNotice)
}
