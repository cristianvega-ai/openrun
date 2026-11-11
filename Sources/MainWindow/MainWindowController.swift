import AppKit
import PaneAppearance
import ProjectsList
import SessionsList

/// The main window: the projects, the sessions of the selected entry, and
/// the content of the selected session, as three panes that lie like
/// stacked sheets (decisions of 2026-10-26 and 2026-11-10). The host gives
/// the lists their content, and the third pane any view.
@MainActor
public final class MainWindowController: NSObject {
    public let projectsList = ProjectsListController()
    public let sessionsList = SessionsListController()
    public weak var delegate: MainWindowDelegate?
    let paneWindow: PaneWindow
    let contentPane = ContentPaneController()
    let splitController = NSSplitViewController()
    let projectsItem: NSSplitViewItem
    let sessionsItem: NSSplitViewItem
    let contentItem: NSSplitViewItem
    let contentShadow = SheetShadowView()
    let sessionsShadow = SheetShadowView()
    let defaults: UserDefaults
    var layout: PaneLayout
    var isContentActive = false
    /// In full screen the traffic lights hide, so no top row keeps room for them.
    var isInFullScreen = false
    /// Whether the window is key. Tests set it, because a test window is not key.
    lazy var isWindowKey: () -> Bool = { [weak paneWindow] in paneWindow?.isKeyWindow ?? false }
    /// The setting of Reduce Motion. Tests set it.
    var reducesMotion = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// - Parameters:
    ///   - defaults: Where the window keeps the layout of its panes.
    ///   - frameName: The name under which AppKit keeps the frame of the window, or `nil` to keep none.
    public init(defaults: UserDefaults = .standard, frameName: String? = "OpenRun Main Window") {
        (self.defaults, layout) = (defaults, PaneLayout.load(from: defaults))
        paneWindow = PaneWindow(contentRect: NSRect(x: 0, y: 0, width: 1_100, height: 700))
        projectsItem = NSSplitViewItem(viewController: Self.holder(of: projectsList.view))
        sessionsItem = NSSplitViewItem(viewController: Self.holder(of: sessionsList.view))
        contentItem = NSSplitViewItem(viewController: Self.holder(of: contentPane.view))
        super.init()
        configurePanes()
        paneWindow.delegate = self
        paneWindow.firstResponderChanged = { [weak self] in self?.updateContentActivity() }
        contentPane.minimumSizeChanged = { [weak self] in self?.keepMinimumSize() }
        keepMinimumSize()
        paneWindow.center()
        if let frameName { paneWindow.setFrameAutosaveName(frameName) }
    }

    /// The window, for the host's menus and for tests.
    public var window: NSWindow { paneWindow }

    public func showWindow() {
        paneWindow.makeKeyAndOrderFront(nil)
    }

    /// Shows the content in the third pane, or its empty state for `nil`.
    public func showContent(_ content: PaneContent?) {
        contentPane.show(content)
    }

    public func updateContentTitle(_ title: String) {
        contentPane.updateTitle(title)
    }

    /// The content has a new minimum size, such as after a change of its text size.
    public func updateContentMinimumSize(_ size: CGSize) {
        contentPane.updateMinimumSize(size)
    }

    private static func holder(of view: NSView) -> NSViewController {
        let holder = NSViewController()
        holder.view = view
        return holder
    }
}
