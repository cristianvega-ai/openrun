import AppKit
import SessionPane
import SessionProtocol
import TerminalView

/// One window that shows one session pane. Closing the window detaches,
/// and the session goes on. The window closes when the program ends.
@MainActor
public final class SessionWindowController: NSObject, NSWindowDelegate, SessionPaneDelegate {
    /// The first size of the content: 80 columns and 24 rows of the standard text, as in Terminal.
    static let contentSize = CGSize(width: 656, height: 388)
    public let window: NSWindow
    let pane: SessionPaneController
    /// Called once when the user closes the window or its program ends.
    public var onClose: (@MainActor () -> Void)?
    private var isClosed = false

    /// - Parameter socket: The socket of the session process: the default one, or the one of `--socket`.
    public init(start: SessionStart, socket: SocketLocation) {
        pane = SessionPaneController(start: start, socket: socket)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        // The controller owns the window, so AppKit must not release it a second time.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = pane.paneView
        window.contentMinSize = pane.minimumSize
        window.center()
        pane.delegate = self
    }

    /// The terminal view of the pane, once the attach brought the snapshot.
    var terminalView: TerminalView? { pane.terminalView }

    /// Shows the window and attaches with the grid that its view will have.
    public func showWindow() {
        window.makeKeyAndOrderFront(nil)
        pane.attach()
    }

    public func windowDidBecomeKey(_ notification: Notification) { pane.activate() }

    public func windowDidResignKey(_ notification: Notification) { pane.deactivate() }

    public func windowWillClose(_ notification: Notification) {
        guard !isClosed else { return }
        isClosed = true
        pane.close()
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
        if terminalView != nil { keepMinimumSize() }
    }

    /// The window cannot become smaller than the minimum grid at the text size
    /// of its view, or than its screen when that grid does not fit there
    /// (decision of 2026-11-08). A user's drag stops there. A larger text size
    /// can leave the window too small, so it grows, and it moves to stay on its
    /// screen.
    private func keepMinimumSize() {
        let screen = window.screen?.visibleFrame
        var minimum = pane.minimumSize
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
