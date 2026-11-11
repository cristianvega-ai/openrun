import Foundation

/// What a session pane tells the host that holds it.
@MainActor
public protocol SessionPaneDelegate: AnyObject {
    /// The program set a new title, or the attach brought the first one.
    /// `SessionPaneController.title` holds it too.
    func sessionPane(_ pane: SessionPaneController, didChangeTitle title: String)

    /// The text size or the screen changed, so `minimumSize` changed.
    func sessionPaneDidChangeMinimumSize(_ pane: SessionPaneController)

    /// The program ended, or the connection failed and the user saw why.
    /// The host removes the pane and calls `close()`.
    func sessionPaneDidEnd(_ pane: SessionPaneController)
}
