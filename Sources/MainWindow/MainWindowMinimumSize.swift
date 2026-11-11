import AppKit
import PaneAppearance

/// The window cannot become smaller than its visible lists and the minimum
/// size of the content of the third pane, such as the minimum grid of a
/// session at its text size (decision of 2026-11-08).
extension MainWindowController: NSWindowDelegate {
    /// A user's drag stops at the minimum. A larger text size can leave the
    /// window too small, so it grows and moves to stay on its screen. When
    /// the minimum does not fit the screen, the screen limits the window.
    func keepMinimumSize() {
        let content = contentPane.minimumSize
        contentItem.minimumThickness = content.width
        var minimum = NSSize(width: layout.minimumWidth(content: content.width), height: PaneTopRow.height + content.height)
        let screen = paneWindow.screen?.visibleFrame
        if let screen {
            let room = paneWindow.contentRect(forFrameRect: screen).size
            minimum = NSSize(width: min(minimum.width, room.width), height: min(minimum.height, room.height))
        }
        paneWindow.contentMinSize = minimum
        // The content view fills the whole window, under the top row too, as
        // the minimum does. The layout rect leaves out the top row.
        let current = paneWindow.contentRect(forFrameRect: paneWindow.frame).size
        guard current.width < minimum.width || current.height < minimum.height else { return }
        let size = NSSize(width: max(current.width, minimum.width), height: max(current.height, minimum.height))
        var frame = paneWindow.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        // The top left corner stays, as when the user drags the bottom right one.
        frame.origin = NSPoint(x: paneWindow.frame.minX, y: paneWindow.frame.maxY - frame.height)
        if let screen {
            frame.origin.x = max(screen.minX, min(frame.origin.x, screen.maxX - frame.width))
            frame.origin.y = max(screen.minY, min(frame.origin.y, screen.maxY - frame.height))
        }
        paneWindow.setFrame(frame, display: true)
    }

    /// A program can set a size below the minimum, which AppKit allows. A
    /// resize can come from a layout pass, and a new size or minimum inside
    /// that pass starts the pass again without end. So the check waits for
    /// a later turn of the main queue.
    public func windowDidResize(_ notification: Notification) {
        guard !isMinimumCheckWaiting else { return }
        isMinimumCheckWaiting = true
        Task { [weak self] in
            self?.isMinimumCheckWaiting = false
            self?.keepMinimumSize()
        }
    }

    /// A window on a screen of another size can have another minimum.
    public func windowDidChangeScreen(_ notification: Notification) {
        keepMinimumSize()
    }
}
