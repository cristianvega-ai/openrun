import AppKit
import PaneAppearance

/// The main window. It has no tabs and no title strip: the content fills the
/// whole window, and the top rows of the panes take the place of the title
/// bar. An empty unified toolbar gives the title bar the height of the top
/// rows, so the traffic lights sit on their middle line.
@MainActor
final class PaneWindow: NSWindow {
    /// The host learns of each change of the keyboard focus, for the
    /// activation of the content of the third pane.
    var firstResponderChanged: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        (titlebarAppearsTransparent, titleVisibility, titlebarSeparatorStyle) = (true, .hidden, .none)
        toolbar = NSToolbar(identifier: "MainWindow")
        toolbarStyle = .unified
        (isReleasedWhenClosed, tabbingMode, title) = (false, .disallowed, "OpenRun")
        collectionBehavior.insert(.fullScreenPrimary)
    }

    /// The room that the traffic lights take at the start of a top row.
    var trafficLightsSpace: CGFloat {
        (standardWindowButton(.zoomButton)?.frame.maxX).map { $0 + 16 } ?? 84
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let result = super.makeFirstResponder(responder)
        firstResponderChanged?()
        return result
    }
}
