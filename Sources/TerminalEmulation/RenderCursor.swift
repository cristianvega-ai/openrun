/// The cursor as a renderer draws it.
public struct RenderCursor: Equatable, Sendable {
    /// The cell under the cursor, or `nil` when the cursor is outside the
    /// visible rows, such as while the user has scrolled up.
    public var position: TerminalCursorPosition?
    public var isOnWideCharacterTail: Bool
    /// Whether the program shows the cursor (DECTCEM).
    public var isVisible: Bool
    public var isBlinking: Bool
    public var isAtPasswordInput: Bool
    public var style: CursorStyle
}
