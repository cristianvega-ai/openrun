import AppKit

/// What the third pane shows: any view of the host, such as a terminal
/// session or a chat, with its own minimum size and the controls that it
/// puts in the top row of the pane (proposal 1 of 2026-11-10).
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

    public init(view: NSView, title: String, minimumSize: CGSize, topRowItems: [NSView] = [], focusView: NSView? = nil) {
        (self.view, self.title, self.minimumSize, self.topRowItems) = (view, title, minimumSize, topRowItems)
        self.focusView = focusView ?? view
    }

    public init(viewController: NSViewController, title: String, minimumSize: CGSize, topRowItems: [NSView] = [], focusView: NSView? = nil) {
        self.init(view: viewController.view, title: title, minimumSize: minimumSize, topRowItems: topRowItems, focusView: focusView)
        self.viewController = viewController
    }
}
