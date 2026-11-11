import AppKit

/// What the third pane shows: any view of the host, such as a terminal
/// session or a chat, with its own minimum size and the controls that it
/// puts in the top row of the pane (proposal 1 of 2026-11-10).
///
/// While the panes change their widths in an animation or a drag, the view
/// keeps its width, and it gets the final width in one layout at the end.
/// So a view that reports its size, such as a terminal, reports it once.
@MainActor
public struct PaneContent {
    public var view: NSView
    /// The view controller of the view, which the pane keeps while it shows the view.
    public var viewController: NSViewController?
    public var title: String
    /// The smallest size of the view. The window keeps room for it.
    public var minimumSize: CGSize
    /// A small set of controls, such as a switch between chat and terminal, or split buttons.
    public var topRowItems: [NSView]
    /// The view that takes the keyboard focus when the pane gets it.
    public var focusView: NSView
    /// The distance from the leading edge of the view to its text. The title
    /// of the pane starts at the same distance, so the two line up.
    public var textInset: CGFloat

    public init(view: NSView, title: String, minimumSize: CGSize, topRowItems: [NSView] = [], focusView: NSView? = nil, textInset: CGFloat = 16) {
        (self.view, self.title, self.minimumSize, self.topRowItems) = (view, title, minimumSize, topRowItems)
        (self.focusView, self.textInset) = (focusView ?? view, textInset)
    }

    public init(viewController: NSViewController, title: String, minimumSize: CGSize, topRowItems: [NSView] = [],
                focusView: NSView? = nil, textInset: CGFloat = 16) {
        self.init(view: viewController.view, title: title, minimumSize: minimumSize, topRowItems: topRowItems, focusView: focusView, textInset: textInset)
        self.viewController = viewController
    }
}
