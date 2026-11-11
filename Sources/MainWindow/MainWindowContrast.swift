import AppKit

/// The colors of the theme follow Increase Contrast, but AppKit draws a view
/// again only when its appearance changes. So a change of the setting draws
/// every view of the window again, and the layer marks take new colors in
/// their next update.
extension MainWindowController {
    func observeDisplayOptions() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @objc func displayOptionsChanged(_ notification: Notification) {
        drawAgain(paneWindow.contentView)
    }

    private func drawAgain(_ view: NSView?) {
        guard let view else { return }
        view.needsDisplay = true
        view.subviews.forEach(drawAgain)
    }
}
