import Foundation

/// One row of the sessions list: one terminal and its splits (decision
/// of 2026-11-10).
public struct LayoutRow: Codable, Equatable, Sendable {
    /// Stays the same for the life of the row. A new row takes the
    /// identifier of its first session, and keeps it when that session
    /// ends before the others.
    public var identifier: UUID
    public var pane: LayoutPane

    public init(identifier: UUID, pane: LayoutPane) {
        (self.identifier, self.pane) = (identifier, pane)
    }

    /// A row for one session.
    public init(session: UUID) {
        self.init(identifier: session, pane: .session(session))
    }
}
