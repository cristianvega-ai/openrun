import AppKit
import PaneAppearance

/// The split view of the three panes, with thin dividers in the theme's divider color.
@MainActor
final class PaneSplitView: NSSplitView {
    override var dividerColor: NSColor { PaneColor.divider }
}
