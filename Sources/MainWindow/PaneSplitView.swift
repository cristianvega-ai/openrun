import AppKit
import PaneAppearance

/// The split view of the three panes, with thin dividers in the theme's divider color.
@MainActor
final class PaneSplitView: NSSplitView {
    override var dividerColor: NSColor { PaneColor.divider }
    /// The user starts and ends a drag of a divider. NSSplitView tracks the
    /// drag inside mouseDown, so the call returns when the drag ends.
    var dragStarted: (() -> Void)?
    var dragEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        dragStarted?()
        super.mouseDown(with: event)
        dragEnded?()
    }
}
