import AppKit
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import MainWindow
@testable import SessionPane

/// Turns of the main run loop. Under load the session can take seconds, so
/// a wait can have a condition. The sleep lets go of the main queue, so the
/// completion of an animation can run.
@MainActor
func turns(seconds: Double, until condition: () -> Bool = { false }) async {
    let end = Date().addingTimeInterval(seconds)
    while !condition(), Date() < end {
        runLoopTurn()
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// Swift does not let an async function run the run loop.
@MainActor
func runLoopTurn() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
}

/// A main window with Reduce Motion off and a real session in its third pane.
@MainActor
func withHostedSession(_ body: (MainWindowController, SessionPaneController) async throws -> Void) async throws {
    let folder = try RunningSessionProcess.makeDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let process = try RunningSessionProcess()
    defer { process.stop() }
    let identifier = try process.createSession(program: ["/bin/sh", "-i"], folder: folder, environment: ["HOME": folder.path, "PATH": "/usr/bin:/bin"])
    let controller = makeMainWindow()
    defer { controller.window.close() }
    controller.reducesMotion = { false }
    controller.window.setContentSize(NSSize(width: 1_280, height: 760))
    let pane = SessionPaneController(start: .runningSession(try #require(UUID(uuidString: identifier))), socket: try SocketLocation(path: process.socketPath))
    defer { pane.close() }
    controller.showContent(PaneContent(pane.content))
    controller.showWindow()
    pane.attach()
    await turns(seconds: 20) { pane.terminalView != nil }
    await turns(seconds: 0.5)
    try await body(controller, pane)
}

/// The map that a host of a session pane makes from the value of the pane.
extension PaneContent {
    init(_ session: SessionPaneContent, topRowItems: [NSView] = []) {
        self.init(view: session.view, title: session.title, minimumSize: session.minimumSize, topRowItems: topRowItems,
                  focusView: session.focusView, textInset: session.textInset)
    }
}
