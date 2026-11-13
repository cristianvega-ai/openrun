import AppKit

/// The view that scrolls in the settings window. Its top is its start,
/// so a pane that is shorter than the window stays at the top.
@MainActor final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
