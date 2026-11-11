import AlertNotifications
import AppKit
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import OpenRunApplication
@testable import TerminalView

/// Waits on the main actor until the condition holds or the time passes.
/// The sleep lets go of the main queue, so the feed and the panes can work.
@MainActor
func waitUntil(timeout: Duration = .seconds(20), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    return condition()
}

/// A workspace on a real session process in a temporary folder. Its
/// window keeps no frame and no pane widths between two tests.
@MainActor
struct TestWorkspace {
    let process: RunningSessionProcess
    let workspace: Workspace
    /// Where the window keeps the widths of its panes.
    let defaults: UserDefaults
    let notifier = RecordingNotifier()
    private let defaultsName = "OpenRunTests-\(UUID().uuidString)"

    /// - Parameter process: A session process of the test, such as one
    ///   whose threads run the fake agent. `nil` starts a plain one.
    init(process: RunningSessionProcess? = nil) throws {
        _ = NSApplication.shared
        self.process = try process ?? RunningSessionProcess()
        defaults = try #require(UserDefaults(suiteName: defaultsName))
        workspace = Self.makeHost(socket: try SocketLocation(path: self.process.socketPath), defaults: defaults, notifier: notifier)
    }

    /// A host that keeps no frame, takes no focus and changes no Dock icon.
    /// Its new sessions read no start file of the user.
    static func makeHost(socket: SocketLocation, defaults: UserDefaults, notifier: RecordingNotifier = RecordingNotifier()) -> Workspace {
        let workspace = Workspace(socket: socket, defaults: defaults, frameName: nil, notifier: notifier)
        workspace.setBadge = { _ in }
        workspace.activateApplication = {}
        workspace.window.window.setContentSize(NSSize(width: 1_100, height: 700))
        workspace.home = socket.folder
        workspace.sessionEnvironment = ["HOME": socket.folder, "ZDOTDIR": socket.folder, "PATH": "/usr/bin:/bin", "PS1": "test> "]
        return workspace
    }

    /// Starts a shell with a prompt that a test can wait for.
    func createShell() throws -> UUID {
        let environment = ["HOME": process.directory.path, "PATH": "/usr/bin:/bin", "PS1": "test> "]
        return try #require(UUID(uuidString: try process.createSession(program: ["/bin/sh", "-i"], environment: environment)))
    }

    var rowTitles: [String] { workspace.window.sessionsList.content.rows.map(\.title) }
    var shownRows: [UUID] { workspace.window.sessionsList.shownIdentifiers }

    func stop() {
        workspace.stop()
        workspace.window.window.close()
        process.stop()
        UserDefaults().removePersistentDomain(forName: defaultsName)
    }
}

extension TerminalView {
    /// The text on the screen of the view.
    var screenText: String { String(decoding: (try? terminal.formatted(.plainText)) ?? [], as: UTF8.self) }
}

/// A stand-in for the notifications of macOS.
@MainActor final class RecordingNotifier: AlertNotifier {
    var posted: [AlertNotification] = []
    var removed: [String] = []
    var opened: ((String) -> Void)?

    func post(_ notification: AlertNotification) { posted.append(notification) }
    func remove(identifier: String) { removed.append(identifier) }
}
