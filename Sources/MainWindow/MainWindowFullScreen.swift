import AppKit

/// The traffic lights hide in full screen and come back when it ends, so
/// the first visible top row gives their room to its title and takes it back.
extension MainWindowController {
    public func windowWillEnterFullScreen(_ notification: Notification) {
        setFullScreen(true)
    }

    public func windowWillExitFullScreen(_ notification: Notification) {
        setFullScreen(false)
    }

    public func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        setFullScreen(false)
    }

    public func windowDidFailToExitFullScreen(_ window: NSWindow) {
        setFullScreen(true)
    }

    private func setFullScreen(_ fullScreen: Bool) {
        isInFullScreen = fullScreen
        updateTopRowSpaces()
    }
}
