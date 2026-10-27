/// A move of the visible rows through the scrollback.
public enum ViewportScroll: Sendable {
    case toTop
    case toBottom
    /// Negative moves up into the scrollback.
    case byRows(Int)
    /// Counted from the top of the scrollback.
    case toRow(Int)
}
