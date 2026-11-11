import AppKit

/// All that a host needs to show a session pane in its layout. A host such
/// as the main window maps it to its own type, so this module does not
/// depend on the host. The minimum size and the title change, so a host
/// asks again when the delegate reports a change.
@MainActor
public struct SessionPaneContent {
    /// The view that the host puts in its layout.
    public let view: NSView
    public let title: String
    /// The smallest size of the view at the current text size.
    public let minimumSize: CGSize
    /// The view that the host gives the keyboard focus to. Before the attach
    /// it takes the focus itself. After the attach, the terminal view inside
    /// it takes the focus.
    public let focusView: NSView
    /// The distance from the leading edge of the view to the grid.
    public let textInset: CGFloat
}
