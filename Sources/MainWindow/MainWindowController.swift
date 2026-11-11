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
    let paneWindow: PaneWindow
    let contentPane = ContentPaneController()
    let splitController = NSSplitViewController()
    let projectsItem: NSSplitViewItem
    let sessionsItem: NSSplitViewItem
    let contentItem: NSSplitViewItem
    let defaults: UserDefaults
    var layout: PaneLayout

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
        paneWindow.center()
        if let frameName { paneWindow.setFrameAutosaveName(frameName) }
    }

    /// The window, for the host's menus and for tests.
    public var window: NSWindow { paneWindow }

    public func showWindow() {
        paneWindow.makeKeyAndOrderFront(nil)
    }

    private static func holder(of view: NSView) -> NSViewController {
        let holder = NSViewController()
        holder.view = view
        return holder
    }
}
