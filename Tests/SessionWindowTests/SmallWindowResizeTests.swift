import AppKit
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import SessionWindow
@testable import TerminalView

@MainActor @Suite(.serialized, .isolatedThread) struct SmallWindowResizeTests {
    /// A zsh prompt and the keys typed before the window changes size. Each
    /// key sequence is done when the screen shows its `shownText`.
    struct ShellState: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let prompt: String
        let keys: [(typed: String, shownText: String)]
    }

    nonisolated static let states = [
        ShellState(
            testDescription: "a long prompt",
            prompt: "PROMPT='resize-test-abcdefghijklmnopqrstuvwxyz0123456789 ~ %# '",
            keys: [("printf 'output-before-resize\\n'\r", "output-before-resize\nresize-test-")]
        ),
        ShellState(
            testDescription: "a prompt of two lines with a long first line",
            prompt: "PROMPT=$'resize-test-two-line-header-abcdefghijklmnopqrstuvwxyz-0123456789-abcdefghijklmnop\\n%# '",
            keys: [("printf 'output-before-resize\\n'\r", "output-before-resize\nresize-test-")]
        ),
    ]

    /// Starts a window on a session of zsh with the prompt of `state`.
    private static func openWindow(prompt: String, folder: URL, process: RunningSessionProcess) async throws -> (SessionWindowController, String) {
        try (prompt + "\n").write(to: folder.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        let identifier = try process.createSession(
            program: ["/bin/zsh", "-i"], folder: folder,
            environment: ["HOME": folder.path, "ZDOTDIR": folder.path, "PATH": "/usr/bin:/bin"]
        )
        let controller = SessionWindowController(
            start: .runningSession(try #require(UUID(uuidString: identifier))),
            socket: try SocketLocation(path: process.socketPath)
        )
        controller.showWindow()
        await waitOnMainThread { controller.view?.screenText.contains("resize-test-") == true }
        return (controller, identifier)
    }

    /// A user's drag stops at the minimum size of the window. A change of
    /// size by the program does not, so the test stops there itself.
    private static func drag(_ window: NSWindow, to size: NSSize) {
        let minimum = window.contentMinSize
        window.setContentSize(NSSize(width: max(size.width, minimum.width), height: max(size.height, minimum.height)))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    @Test(arguments: states) func aSmallWindowKeepsTheOutputAndOnePrompt(state: ShellState) async throws {
        _ = NSApplication.shared
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let (controller, identifier) = try await Self.openWindow(prompt: state.prompt, folder: folder, process: process)
        defer { controller.window.close() }
        let view = try #require(controller.view)
        for key in state.keys {
            controller.terminalView(view, send: Array(key.typed.utf8))
            await waitOnMainThread { view.screenText.contains(key.shownText) }
            try #require(view.screenText.contains(key.shownText))
        }
        let original = view.screenText.replacingOccurrences(of: "\n", with: "")

        let minimum = SessionWindowController.minimumGrid
        for _ in 0..<2 {
            for step in 0..<160 {
                let distance = step < 80 ? step : 160 - step
                Self.drag(controller.window, to: NSSize(width: max(40, 640 - distance * 8), height: max(20, 388 - distance * 5)))
                view.layoutSubtreeIfNeeded()
                if step == 79 {
                    // The smallest window shows the whole minimum grid, and nothing is hidden.
                    await waitOnMainThread { view.gridSize == minimum }
                    #expect(view.visibleGridSize == minimum)
                    #expect(controller.hiddenGridLabel.isHidden)
                }
                try await Task.sleep(for: .milliseconds(4))
            }
        }
        Self.drag(controller.window, to: NSSize(width: 1200, height: 700))
        view.layoutSubtreeIfNeeded()
        await waitOnMainThread(seconds: 10) { view.gridSize == view.visibleGridSize }
        await waitOnMainThread(seconds: 5) { view.screenText.replacingOccurrences(of: "\n", with: "") == original }
        #expect(view.screenText.replacingOccurrences(of: "\n", with: "") == original)
        #expect(try process.screenText(of: identifier).trimmingCharacters(in: .newlines) == view.screenText)
    }
}
