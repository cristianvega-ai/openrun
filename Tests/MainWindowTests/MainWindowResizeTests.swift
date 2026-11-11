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

    @Test func aDragOfAnEdgeSendsOneSize() async throws {
        try await withHostedSession { controller, pane in
            let before = pane.sentSizeRequests
            let splitView = controller.splitController.splitView
            let edge = controller.frame(of: controller.contentPane.view).minX - 1
            let y = splitView.bounds.midY
            let window = controller.window
            func event(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: splitView.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            for step in 1...12 { NSApplication.shared.postEvent(event(.leftMouseDragged, edge + CGFloat(step * 8)), atStart: false) }
            NSApplication.shared.postEvent(event(.leftMouseUp, edge + 96), atStart: false)
            splitView.mouseDown(with: event(.leftMouseDown, edge))
            // An await here after the tracking loop of the split view
            // ended the test process, so the wait stays synchronous.
            for _ in 0..<1_000 where pane.sentSizeRequests == before { runLoopTurn() }
            for _ in 0..<50 { runLoopTurn() }
            #expect(abs(controller.sessionsList.view.frame.width - 396) < 2)
            #expect(pane.sentSizeRequests == before + 1)
            #expect(pane.paneView.frame.width == controller.contentPane.contentArea.frame.width)
        }
    }
}
