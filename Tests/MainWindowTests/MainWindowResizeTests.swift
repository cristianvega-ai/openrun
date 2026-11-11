import AppKit
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import MainWindow
@testable import SessionPane

/// A change of the widths of the panes gives a session one size, at the end.
@MainActor @Suite(.serialized) struct MainWindowResizeTests {
    /// Under load the session can take seconds, so a wait can have a condition.
    private func turns(seconds: Double, until condition: () -> Bool = { false }) async {
        let end = Date().addingTimeInterval(seconds)
        while !condition(), Date() < end {
            runLoopTurn()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func runLoopTurn() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    private func withHostedSession(_ body: (MainWindowController, SessionPaneController) async throws -> Void) async throws {
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
        controller.showContent(PaneContent(view: pane.paneView, title: "zsh", minimumSize: pane.minimumSize))
        controller.showWindow()
        pane.attach()
        await turns(seconds: 20) { pane.terminalView != nil }
        await turns(seconds: 0.5)
        try await body(controller, pane)
    }

    @Test func oneAnimatedToggleSendsOneSize() async throws {
        try await withHostedSession { controller, pane in
            let before = pane.sentSizeRequests
            for count in 1...2 {
                controller.toggleProjectsList(nil)
                await turns(seconds: 20) { pane.sentSizeRequests >= before + count }
                await turns(seconds: 0.5)
                #expect(pane.sentSizeRequests == before + count)
                #expect(pane.paneView.frame.width == controller.contentPane.contentArea.frame.width)
            }
        }
    }
}
