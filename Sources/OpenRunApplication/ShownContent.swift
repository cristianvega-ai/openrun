import Foundation
import WindowLayout

/// What the third pane shows now.
enum ShownContent: Equatable {
    /// The empty state of the pane.
    case nothing
    /// The pane of a session.
    case session(UUID)
    /// The chat of an agent thread.
    case thread(UUID)
    /// A row with splits: its sessions and threads, as its layout tells.
    case split(row: UUID, pane: LayoutPane)
    case notice(PaneNotice)
}
