import AppKit

/// The pane still owns its window. The next changes give the window a
/// controller of its own around the pane.
public typealias SessionWindowController = SessionPaneController

/// What the window does when its pane reports.
extension SessionPaneController: NSWindowDelegate, SessionPaneDelegate {
    /// Shows the window and attaches with the grid that its view will have.
    public func showWindow() {
        window.makeKeyAndOrderFront(nil)
        attach()
    }

    public func windowDidBecomeKey(_ notification: Notification) { activate() }

    public func windowDidResignKey(_ notification: Notification) { deactivate() }

    public func windowWillClose(_ notification: Notification) {
        guard !isClosed else { return }
        close()
        onClose?()
    }

    public func sessionPane(_ pane: SessionPaneController, didChangeTitle title: String) {
        window.title = title
    }

    public func sessionPaneDidEnd(_ pane: SessionPaneController) {
        window.close()
    }

    public func sessionPaneDidChangeMinimumSize(_ pane: SessionPaneController) {
        keepMinimumSize()
    }

    /// A window on a screen of another size can have another minimum.
    public func windowDidChangeScreen(_ notification: Notification) {
        if view != nil { keepMinimumSize() }
    }

    /// The window cannot become smaller than the minimum grid at the text size
    /// of its view, or than its screen when that grid does not fit there
    /// (decision of 2026-11-08). A user's drag stops there. A larger text size
    /// can leave the window too small, so it grows, and it moves to stay on its
    /// screen.
    private func keepMinimumSize() {
        let screen = window.screen?.visibleFrame
        var minimum = minimumSize
        if let screen {
            let room = window.contentRect(forFrameRect: screen).size
            minimum = NSSize(width: min(minimum.width, room.width), height: min(minimum.height, room.height))
        }
        window.contentMinSize = minimum
        let current = window.contentLayoutRect.size
        guard current.width < minimum.width || current.height < minimum.height else { return }
        let content = NSSize(width: max(current.width, minimum.width), height: max(current.height, minimum.height))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        // The top left corner stays, as when the user drags the bottom right one.
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        if let screen {
            frame.origin.x = max(screen.minX, min(frame.origin.x, screen.maxX - frame.width))
            frame.origin.y = max(screen.minY, min(frame.origin.y, screen.maxY - frame.height))
        }
        window.setFrame(frame, display: true)
    }
}
