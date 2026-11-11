import AppKit
@testable import PaneAppearance
@testable import ProjectsList
import SessionPane
import SessionProcessHarness
import SessionProtocol
@testable import SessionsList
import Testing
@testable import MainWindow

/// Opt in with OPENRUN_RENDER_OUTPUT, a folder, to save pictures of the main
/// window: light and dark with a real session, with Increase Contrast, with
/// legacy scrollers, the empty states, a narrow window, and the first pane hidden.
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"] != nil))
struct MainWindowPictureTests {
    @Test func picturesOfTheMainWindow() async throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.activate()
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let identifier = try process.createSession(program: ["/bin/sh", "-i"], folder: folder,
                                                   environment: ["HOME": folder.path, "PATH": "/usr/bin:/bin", "PS1": "openrun % "])
        let controller = makeMainWindow()
        defer { controller.window.close() }
        controller.reducesMotion = { true }
        controller.window.setContentSize(NSSize(width: 1_280, height: 760))
        var sample = PictureSample()
        controller.projectsList.show(sample.projects)
        controller.projectsList.select(.project(sample.projectIdentifiers[0]))
        controller.sessionsList.show(sample.sessions)
        controller.sessionsList.select(sample.sessions.rows[1].identifier)
        let pane = SessionPaneController(start: .runningSession(try #require(UUID(uuidString: identifier))), socket: try SocketLocation(path: process.socketPath))
        defer { pane.close() }
        let split = PaneButton.make(symbol: "rectangle.split.2x1", label: "Split", target: nil, action: nil)
        var content = PaneContent(pane.content, topRowItems: [split])
        content.title = "Repair the resize"
        controller.showContent(content)
        controller.showWindow()
        controller.window.layoutIfNeeded()
        pane.attach()
        await turns(until: { pane.terminalView != nil })
        _ = try process.runCommand(["send", identifier, "--enter", "printf 'swift test\\n\\033[32m✔\\033[0m Test run with 412 tests passed\\n'"])
        controller.focusContent()
        await turns(seconds: 1.5)
        let appearances: [(String, NSAppearance.Name, Bool)] = [("light", .aqua, false), ("dark", .darkAqua, false),
            ("contrast-light", .aqua, true), ("contrast-dark", .darkAqua, true)]
        for (name, appearance, increasesContrast) in appearances {
            PaneColor.contrastSetting.withLock { $0 = increasesContrast }
            // A new appearance makes each view take the colors again.
            controller.window.appearance = NSAppearance(named: appearance == .aqua ? .darkAqua : .aqua)
            controller.window.appearance = NSAppearance(named: appearance)
            await turns(seconds: 0.6)
            try capture(controller.window, to: output.appendingPathComponent("main-\(name).png"))
        }
        PaneColor.contrastSetting.withLock { $0 = nil }
        controller.window.appearance = NSAppearance(named: .aqua)
        // A Mac with a mouse can ask for legacy scrollers, which AppKit sets on each scroll view.
        (controller.projectsList.scroll.scrollerStyle, controller.sessionsList.scroll.scrollerStyle) = (.legacy, .legacy)
        controller.window.setContentSize(NSSize(width: 1_100, height: 420))
        await turns(seconds: 0.6)
        try capture(controller.window, to: output.appendingPathComponent("main-legacy-scrollers.png"))
        controller.window.setContentSize(controller.window.contentMinSize)
        await turns(seconds: 0.6)
        try capture(controller.window, to: output.appendingPathComponent("main-narrow.png"))
        controller.window.setContentSize(NSSize(width: 1_100, height: 700))
        controller.toggleProjectsList(nil)
        await turns(seconds: 0.6)
        try capture(controller.window, to: output.appendingPathComponent("main-projects-hidden.png"))
        controller.toggleProjectsList(nil)
        controller.projectsList.show(ProjectsListContent())
        controller.sessionsList.show(SessionsListContent(title: "All Sessions", rows: [], agents: ["Claude Code", "Codex"]))
        controller.showContent(nil)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            controller.window.appearance = NSAppearance(named: appearance)
            await turns(seconds: 0.6)
            try capture(controller.window, to: output.appendingPathComponent("main-empty-\(name).png"))
        }
    }

    /// Turns of the main run loop, so AppKit draws and the session answers.
    private func turns(seconds: Double = 5, until condition: () -> Bool = { false }) async {
        let end = Date().addingTimeInterval(seconds)
        while !condition(), Date() < end {
            runLoopTurn()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Swift does not let an async function run the run loop.
    private func runLoopTurn() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    private func capture(_ window: NSWindow, to path: URL) throws {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), path.path]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0 && FileManager.default.fileExists(atPath: path.path))
    }
}
