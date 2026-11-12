import AppKit

/// The settings window (decision of 2026-10-15): one pane for each group
/// of settings, as in every Mac app.
///
/// The window changes nothing itself. It tells its host the name and the
/// new text of a setting, the host sends them to the session process, and
/// the texts that come back show in the controls. So a value that the
/// session process refused never stays on the screen.
@MainActor public final class SettingsWindowController: NSWindowController {
    let panes: [SettingsPaneController]
    /// The name of a setting and the new text of its value.
    public var change: ((_ name: String, _ text: String) -> Void)?

    /// - Parameter permissionModeTitle: The words of the app for a
    ///   permission mode of Claude Code, as the chat shows them.
    public init(permissionModeTitle: @escaping (String) -> String) {
        panes = SettingsPane.all(permissionModeTitle: permissionModeTitle).map(SettingsPaneController.init)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: true)
        super.init(window: window)
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        for pane in panes {
            let item = NSTabViewItem(viewController: pane)
            (item.label, item.image) = (pane.pane.title, NSImage(systemSymbolName: pane.pane.symbolName, accessibilityDescription: nil))
            tabs.addTabViewItem(item)
            pane.changed = { [weak self] name, text in self?.change?(name, text) }
        }
        (window.contentViewController, window.isReleasedWhenClosed) = (tabs, false)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the texts of the settings as the session process gives them:
    /// at the start, after each change, and after a refused change.
    public func show(_ texts: [String: String]) {
        for pane in panes { pane.show(texts) }
    }
}
