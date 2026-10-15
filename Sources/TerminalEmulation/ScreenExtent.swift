/// How much of the screen `Terminal.formatted` includes.
public enum ScreenExtent: Equatable, Sendable {
    /// The rows that fit in the terminal's size.
    case visible
    /// The scrollback followed by the visible rows.
    case withScrollback
}
