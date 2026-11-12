import AppKit

/// The panes of the settings window as tabs in its toolbar. The window
/// takes the height of the pane that shows, and its top edge stays.
@MainActor final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        guard let window = view.window, let size = item?.view?.fittingSize else { return }
        let content = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        (frame.origin.y, frame.size) = (frame.maxY - content.height, content.size)
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}
