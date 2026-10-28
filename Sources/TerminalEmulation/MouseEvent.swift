/// One mouse event for a program that asked for mouse reports.
public struct MouseEvent: Sendable {
    /// The raw values of both enums are the numbers of libghostty-vt.
    public enum Action: Int32, Sendable { case press, release, motion }
    /// A wheel turn is a press of a wheel button, as in X11.
    public enum Button: Int32, Sendable {
        case left = 1, right, middle, wheelUp, wheelDown, wheelLeft, wheelRight, back, forward
    }

    public var action: Action
    /// `nil` for a motion with no button held.
    public var button: Button?
    public var modifiers: KeyModifiers
    /// The pointer in pixels from the top left of the grid.
    public var horizontalPosition, verticalPosition: Float

    public init(action: Action, button: Button?, modifiers: KeyModifiers = [], horizontalPosition: Float, verticalPosition: Float) {
        (self.action, self.button, self.modifiers, self.horizontalPosition, self.verticalPosition) = (action, button, modifiers, horizontalPosition, verticalPosition)
    }
}
