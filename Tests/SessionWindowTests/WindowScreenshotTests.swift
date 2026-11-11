import AppKit
import LiveDisplay
import SessionProcessHarness
import SessionProtocol
import TerminalEmulation
import Testing
@testable import SessionWindow
@testable import TerminalView

/// Opt in with OPENRUN_RENDER_OUTPUT to save pictures of a real session window.
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"] != nil), .needsLiveDisplay)
struct WindowScreenshotTests {
    @Test func picturesOfTheSessionWindow() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let identifier = try process.createSession(program: ["/bin/sh", "-i"], folder: folder, environment: ["HOME": folder.path, "PATH": "/usr/bin:/bin", "PS1": "openrun> "])
        let location = try SocketLocation(path: process.socketPath)
        let controller = SessionWindowController(start: .runningSession(try #require(UUID(uuidString: identifier))), socket: location)
        controller.showWindow()
        defer { controller.window.close() }
        await waitOnMainThread { controller.view != nil }
        let view = try #require(controller.view)
        try send("printf '\\033[2J\\033[HOpenRun screenshot\\n\\033[32mGreen %s\\033[0m\\n' 'terminal output'", to: identifier, process: process)
        await waitOnMainThread { view.screenText.contains("Green terminal output") }
        try #require(view.screenText.contains("Green terminal output"))
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            controller.window.appearance = NSAppearance(named: appearance)
            let background = name == "light" ? TerminalColor(red: 250, green: 251, blue: 252) : TerminalColor(red: 30, green: 32, blue: 34)
            await waitOnMainThread { view.theme.background == background }
            try #require(view.theme.background == background)
            try await showNextFrame(view)
            let path = output.appendingPathComponent("window-\(name).png")
            try capture(controller.window, to: path)
            try checkBackground(path, expected: background)
        }
        try send("printf '\\033[?1049h\\033[H%s %s\\n\\033[33mYellow text\\033[0m\\n' 'Alternate' 'screen'", to: identifier, process: process)
        await waitOnMainThread { view.terminal.isAlternateScreenActive && view.screenText.contains("Alternate screen") }
        try #require(view.terminal.isAlternateScreenActive && view.screenText.contains("Alternate screen"))
        try await showNextFrame(view)
        try capture(controller.window, to: output.appendingPathComponent("window-alternate.png"))
        let visible = try #require(view.visibleGridSize)
        let other = try SessionStart.runningSession(try #require(UUID(uuidString: identifier))).attach(
            at: location, size: SessionSize(columns: visible.columns + 40, rows: visible.rows + 20))
        defer { other.attachment.shutdown() }
        await waitOnMainThread { !controller.hiddenGridLabel.isHidden }
        #expect(!controller.hiddenGridLabel.isHidden)
        try await showNextFrame(view)
        try capture(controller.window, to: output.appendingPathComponent("window-hidden-grid.png"))
        let question = Task { await controller.terminalView(view, shouldOpenLink: "file:///tmp/openrun-example") }
        await waitOnMainThread { controller.window.attachedSheet?.isVisible == true }
        let sheet = try #require(controller.window.attachedSheet)
        try capture(sheet, to: output.appendingPathComponent("window-link-question.png"))
        controller.window.endSheet(sheet, returnCode: .alertSecondButtonReturn)
        #expect(!(await question.value))
    }

    private func showNextFrame(_ view: TerminalView) async throws {
        let previous = view.framesDrawn
        view.requestFrame()
        await waitOnMainThread { view.framesDrawn > previous }
        try #require(view.framesDrawn > previous)
        await waitOnMainThread(seconds: 1) { false }
    }

    private func checkBackground(_ path: URL, expected: TerminalColor) throws {
        let picture = try #require(NSBitmapImageRep(data: Data(contentsOf: path)))
        let color = try #require(picture.colorAt(x: picture.pixelsWide / 2, y: picture.pixelsHigh / 2))
        #expect(abs(color.redComponent * 255 - CGFloat(expected.red)) < 5)
        #expect(abs(color.greenComponent * 255 - CGFloat(expected.green)) < 5)
        #expect(abs(color.blueComponent * 255 - CGFloat(expected.blue)) < 5)
    }

    private func send(_ text: String, to identifier: String, process: RunningSessionProcess) throws {
        let result = try process.runCommand(["send", identifier, "--enter", text])
        #expect(result.status == 0)
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
