import AppKit
import PaneAppearance

/// The settings window (decisions of 2026-10-15 and 2026-11-12): the
/// list of the panes at the left, and the settings of one pane at the
/// right, in the colors of the main window.
///
/// The window changes nothing itself. It tells its host the name and the
/// new text of a setting, the host sends them to the session process, and
/// the texts that come back show in the controls. So a value that the
/// session process refused never stays on the screen.
@MainActor public final class SettingsWindowController: NSWindowController {
    let panes: [SettingsPaneController]
    let sidebar: SettingsSidebarController
    let content: SettingsContentController
    /// The name of a setting and the new text of its value.
    public var change: ((_ name: String, _ text: String) -> Void)?

    /// - Parameter permissionModeTitle: The words of the app for a
    ///   permission mode of Claude Code, as the chat shows them.
    public init(permissionModeTitle: @escaping (String) -> String) {
        let groups = SettingsPane.groups(permissionModeTitle: permissionModeTitle)
        panes = groups.flatMap { $0 }.map(SettingsPaneController.init)
        (sidebar, content) = (SettingsSidebarController(groups: groups), SettingsContentController(panes: panes))
        let width = SettingsSidebarController.width + 1 + SettingsCardView.width + 64
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        super.init(window: window)
        (window.title, window.titleVisibility, window.titlebarAppearsTransparent, window.isReleasedWhenClosed) = ("Settings", .hidden, true, false)
        // An empty unified toolbar gives the title bar the height of the top rows, as in the main window.
        (window.toolbar, window.toolbarStyle) = (NSToolbar(identifier: "Settings"), .unified)
        // The window has one width, so the lines of text end at known places. Its height follows the user.
        (window.contentMinSize, window.contentMaxSize) = (NSSize(width: width, height: 420), NSSize(width: width, height: 4_000))
        // The color of the root shows as a line between the two parts.
        let root = PaneBackgroundView(color: PaneColor.divider)
        for view in [sidebar.view, content.view] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            NSLayoutConstraint.activate([view.topAnchor.constraint(equalTo: root.topAnchor), view.bottomAnchor.constraint(equalTo: root.bottomAnchor)])
        }
        NSLayoutConstraint.activate([
            sidebar.view.leadingAnchor.constraint(equalTo: root.leadingAnchor), content.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.view.leadingAnchor.constraint(equalTo: sidebar.view.trailingAnchor, constant: 1),
        ])
        window.contentView = root
        for pane in panes { pane.changed = { [weak self] name, text in self?.change?(name, text) } }
        sidebar.chose = { [content] in content.show(pane: $0) }
        sidebar.searched = { [content, sidebar] text in
            content.search(text)
            // An empty search goes back to the pane from before it.
            if !content.isSearching { sidebar.select(pane: content.shownPane) }
        }
        sidebar.select(pane: 0)
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
