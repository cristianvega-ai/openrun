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
    private let defaultsName = "OpenRunTests-\(UUID().uuidString)"

    init() throws {
        _ = NSApplication.shared
        process = try RunningSessionProcess()
        defaults = try #require(UserDefaults(suiteName: defaultsName))
        workspace = Workspace(socket: try SocketLocation(path: process.socketPath), defaults: defaults, frameName: nil)
        workspace.window.window.setContentSize(NSSize(width: 1_100, height: 700))
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
