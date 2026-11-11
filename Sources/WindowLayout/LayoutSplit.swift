/// Two panes that share the room of one, with the part that the first one
/// takes.
public struct LayoutSplit: Codable, Equatable, Sendable {
    public enum Direction: String, Codable, Sendable {
        /// The panes lie side by side.
        case sideBySide
        /// The first pane lies over the second.
        case stacked
    }

    public var direction: Direction
    /// The part of the room that the first pane takes, from 0 to 1.
    public var fraction: Double
    public var first: LayoutPane
    public var second: LayoutPane

    public init(direction: Direction, fraction: Double = 0.5, first: LayoutPane, second: LayoutPane) {
        (self.direction, self.fraction, self.first, self.second) = (direction, min(max(fraction, 0), 1), first, second)
    }
}
