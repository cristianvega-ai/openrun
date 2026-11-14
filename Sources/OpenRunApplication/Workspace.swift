import AccountUsage
import AlertNotifications
import AppKit
import BrowserPane
import DataStorage
import ListContent
import MainWindow
import PaneSplits
import ProjectsList
import PseudoTerminal
import SessionOverview
import SessionPane
import SessionProtocol
import SessionsList
import Settings
import SettingsWindow
import ToolInstallation
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
    let threadPanes = ThreadPanes()
    /// The last usage reading of each account, as `account-usage.json` keeps them.
    let usageStore: AccountUsageStore
    var keptUsage: [AccountUsageReading]
    /// The web pages of the rows, from the first time that a row shows one.
    var browserPanes: [UUID: BrowserPaneController] = [:]
    /// Where the app keeps what the user chose last, such as the account of a new thread.
    let defaults: UserDefaults
    /// Whether the web pages keep their data, such as a login. A test keeps none.
    var keepsWebsiteData = true
    /// The view of the row with splits that the third pane shows.
    var splitView: SplitPaneView?
    /// The pane of a row with splits that had the keyboard focus last,
    /// and the new pane of a split that takes the focus when it shows.
    var lastFocusedLeaf: UUID?
    var leafToFocus: UUID?
    /// The settings window, from its first use.
    var settingsWindow: SettingsWindowController?
    /// The window with the keyboard. A test gives its own.
    var keyWindow: () -> NSWindow? = { NSApp.keyWindow }
    let notifier: any AlertNotifier
    /// The rows, the selection, the filter and the order, as `layout.json` keeps them.
    var layout: WindowLayout
    var savedLayout: WindowLayout
    var settings = SettingValues()
    /// What the third pane shows. It is stale when the pane of its
    /// session closed, so the next refresh shows other content.
    var shown = ShownContent.nothing
    var shownIsStale = false
    /// Sessions whose pane lost its connection while the session runs, and
    /// sessions whose program ended before the feed said so.
    var lostSessions: Set<UUID> = []
    var exitedSessions: Set<UUID> = []
    /// The time of the alert of each session that the host asked to end.
    var clearedAlerts: [UUID: Date] = [:]
    /// The number on the Dock icon: the rows that need the user.
    var badgeCount = 0
    /// Puts the number on the Dock icon. Tests set it.
    var setBadge: (Int) -> Void = { NSApp.dockTile.badgeLabel = $0 > 0 ? String($0) : nil }
    /// Brings the app to the front. Tests set it, so a test takes no focus.
    var activateApplication: () -> Void = { NSApp.activate() }
    /// Whether the window is key and the keyboard focus is in the third pane.
    var isContentActive = false
    /// A session or a thread that the user asked for. Its row takes the
    /// selection and the keyboard focus when the feed brings it.
    var sessionToSelect: UUID?
    /// A project that takes the selection of the first pane when the feed
    /// brings it: one that the user added, or the kept one at the start.
    var projectToSelect: UUID?
    /// Whether the host follows the session process.
    private(set) var isStarted = false
    /// Whether the window shows a session after the first list of the
    /// feed, so the user gets a terminal at once: the kept row, or else
    /// the first row, or else a new login shell when no session runs.
    var showsSessionAtStart = false
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
    /// Asks about a restart of the session process. Tests set it.
    lazy var confirmRestart: (NSAlert, @escaping (Bool) -> Void) -> Void = { [weak self] in self?.askBeforeRestart($0, then: $1) }
    /// Reads the build of the session process in the bundle of this app. Tests set it.
    var readBundledBuild: @Sendable () -> String? = BundledSessionProcess.buildIdentifier
    /// The builds of the session process that the app compared with its own, so the user hears of each one time.
    var knownBuilds: Set<String> = []
    /// Asks before the close of a thread with this title. Tests set it.
    lazy var confirmCloseOfThread: (String, @escaping (Bool) -> Void) -> Void = { [weak self] in self?.askBeforeCloseOfThread($0, then: $1) }
    /// The install of the command-line tool of this app bundle, or nil
    /// outside a bundle. Tests set it, with its questions.
    var toolInstallation = ToolInstallation(bundlePath: Bundle.main.bundlePath)
    lazy var confirmToolInstallation: (ToolInstallation, @escaping (Bool) -> Void) -> Void = { [weak self] in self?.askBeforeToolInstallation($0, then: $1) }
    var runAsAdministrator: (String) throws -> Void = AdministratorCommandFailure.run
    lazy var tellToolInstallation: (String, String) -> Void = { [weak self] in self?.showToolInstallationResult($0, $1) }
    /// Tells why a setting did not change. Tests set it.
    lazy var showSettingFailure: (String) -> Void = { [weak self] in self?.showSettingFailureSheet($0) }
    /// Asks for the folders of new projects. Tests set it.
    lazy var chooseProjectFolders: (@escaping ([URL]) -> Void) -> Void = { [weak self] in self?.chooseFoldersInPanel(then: $0) }

    /// - Parameters:
    ///   - defaults: Where the window keeps the widths of its panes.
    ///   - frameName: The name under which AppKit keeps the frame of the window, or `nil` to keep none.
    init(
        socket: SocketLocation, defaults: UserDefaults = .standard, frameName: String? = "OpenRun Main Window",
        notifier: any AlertNotifier = SystemAlertNotifier()
    ) {
        (self.socket, self.notifier) = (socket, notifier)
        self.defaults = defaults
        window = MainWindowController(defaults: defaults, frameName: frameName)
        connection = SessionOverviewConnection(socket: socket)
        requests = SessionRequests(socket: socket)
        // The data folder of the app is the folder of its socket, so an
        // app on a temporary socket never touches the data of the user.
        layoutStore = WindowLayoutStore(dataFolder: DataFolder(path: socket.folder))
        layout = layoutStore.load()
        usageStore = AccountUsageStore(dataFolder: DataFolder(path: socket.folder))
        keptUsage = usageStore.load()
        savedLayout = layout
        panes = SessionPanes { SessionPaneController(start: .runningSession($0), socket: socket) }
        super.init()
        window.sessionsList.arrange(filter: SessionsFilter(rawValue: layout.filter) ?? .all, order: SessionsOrder(rawValue: layout.order) ?? .manual)
        window.sessionsList.delegate = self
        window.projectsList.delegate = self
        // The projects come with the feed, so a kept project waits for it.
        if case .project(let identifier) = layout.selectedEntry { projectToSelect = identifier }
        window.projectsList.select(ProjectsListEntry(layout.selectedEntry))
        window.delegate = self
        connection.overviewChanged = { [weak self] in self?.overviewChanged(from: $0) }
        connection.statusChanged = { [weak self] in self?.statusChanged() }
        notifier.opened = { [weak self] in self?.openNotification($0) }
    }

    /// Shows the window and starts to follow the session process. The
    /// window comes at once, and the lists fill when the feed answers.
    func start() {
        showWindow()
        isStarted = true
        connection.start()
    }

    /// Shows the window again after the user closed it, with the selected row.
    func showWindow() {
        window.showWindow()
        refresh()
    }

    /// Detaches every pane and writes the layout. The sessions go on.
    func stop() {
        connection.stop()
        panes.closeAll()
        threadPanes.closeAll()
        layoutStore.save(layout)
        layoutStore.finishWrites()
    }
}
