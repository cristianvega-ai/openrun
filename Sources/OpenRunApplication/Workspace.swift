import AppKit
import DataStorage
import ListContent
import MainWindow
import ProjectsList
import PseudoTerminal
import SessionOverview
import SessionPane
import SessionProtocol
import SessionsList
import Settings
import WindowLayout

/// The host of the main window. It joins the window with the session
/// process: it gives the lists their content after each batch of changes,
/// shows the session of the selected row in the third pane, and sends
/// what the user does to the session process (decision of 2026-11-10).
@MainActor
final class Workspace: NSObject {
    let socket: SocketLocation
    let window: MainWindowController
    let connection: SessionOverviewConnection
    let requests: SessionRequests
    let layoutStore: WindowLayoutStore
    let panes: SessionPanes
    /// The rows, the selection, the filter and the order, as `layout.json` keeps them.
    var layout: WindowLayout
    var savedLayout: WindowLayout
    var settings = SettingValues()
    /// The session whose pane the third pane shows.
    var shownSession: UUID?
    /// Whether the window is key and the keyboard focus is in the third pane.
    var isContentActive = false
    /// A session that the user asked for. Its row takes the selection
    /// and the keyboard focus when the feed brings the session.
    var sessionToSelect: UUID?
    /// The lists report a selection while they take new content, and that
    /// is no choice of the user.
    var isRefreshing = false
    /// The home folder, which the rows show as `~`, and where a session
    /// outside every project starts. Tests set it.
    var home = NSHomeDirectory()
    /// The environment and the shell of a new session. Tests set them,
    /// so no test reads the start files of the user.
    var sessionEnvironment = ProcessInfo.processInfo.environment
    var loginShell = LoginShell.current()
    /// Shows a failure of a request, with a title and the reason. Tests set it.
    lazy var showFailure: (String, String) -> Void = { [weak self] in self?.showFailureSheet(title: $0, message: $1) }
    /// Asks before a close and gives the answer. Tests set it.
    lazy var confirmClose: (CloseQuestion, @escaping (Bool) -> Void) -> Void = { [weak self] in self?.askBeforeClose($0, then: $1) }

    /// - Parameters:
    ///   - defaults: Where the window keeps the widths of its panes.
    ///   - frameName: The name under which AppKit keeps the frame of the window, or `nil` to keep none.
    init(socket: SocketLocation, defaults: UserDefaults = .standard, frameName: String? = "OpenRun Main Window") {
        self.socket = socket
        window = MainWindowController(defaults: defaults, frameName: frameName)
        connection = SessionOverviewConnection(socket: socket)
        requests = SessionRequests(socket: socket)
        // The data folder of the app is the folder of its socket, so an
        // app on a temporary socket never touches the data of the user.
        layoutStore = WindowLayoutStore(dataFolder: DataFolder(path: socket.folder))
        layout = layoutStore.load()
        savedLayout = layout
        panes = SessionPanes { SessionPaneController(start: .runningSession($0), socket: socket) }
        super.init()
        window.sessionsList.arrange(filter: SessionsFilter(rawValue: layout.filter) ?? .all, order: SessionsOrder(rawValue: layout.order) ?? .manual)
        window.sessionsList.delegate = self
        connection.overviewChanged = { [weak self] in self?.overviewChanged(from: $0) }
    }

    /// Shows the window and starts to follow the session process. The
    /// window comes at once, and the lists fill when the feed answers.
    func start() {
        window.showWindow()
        connection.start()
    }

    /// Detaches every pane and writes the layout. The sessions go on.
    func stop() {
        connection.stop()
        panes.closeAll()
        layoutStore.save(layout)
        layoutStore.finishWrites()
    }
}
