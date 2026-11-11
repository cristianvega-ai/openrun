import AppKit
import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import TerminalView
@testable import SessionPane

/// Lets the main thread work until `condition` is true or `seconds` have passed.
/// The pane gets the events of its session through the main queue, which
/// runs only while the test waits.
@MainActor
func waitOnMainThread(seconds: Double = 5, until condition: () -> Bool) async {
    let end = Date().addingTimeInterval(seconds)
    while !condition(), Date() < end {
        runLoopTurn()
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// One short turn of the main run loop. Swift does not let an async function run it.
@MainActor
private func runLoopTurn() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.005))
}

/// Plays the host of a pane and keeps what the pane reports.
@MainActor
final class RecordingHost: SessionPaneDelegate {
    var titles: [String] = []
    var minimumSizeReports = 0
    var ends = 0
    var failures: [String] = []

    func sessionPane(_ pane: SessionPaneController, didChangeTitle title: String) { titles.append(title) }
    func sessionPaneDidChangeMinimumSize(_ pane: SessionPaneController) { minimumSizeReports += 1 }
    func sessionPaneDidEnd(_ pane: SessionPaneController) { ends += 1 }
    func sessionPane(_ pane: SessionPaneController, didFailWithMessage message: String) { failures.append(message) }
}

extension TerminalView {
    /// The text on the screen of the view.
    var screenText: String { String(decoding: (try? terminal.formatted(.plainText)) ?? [], as: UTF8.self) }
}

/// A pane that a test window holds beside another control.
struct HostedPane {
    let pane: SessionPaneController, host: RecordingHost, window: NSWindow, identifier: String
}

/// Starts a shell session and attaches a pane to it at the right of a text field.
@MainActor
func hostPane(in process: RunningSessionProcess, folder: URL, focusesPane: Bool = true) async throws -> HostedPane {
    _ = NSApplication.shared
    let identifier = try process.createSession(program: ["/bin/sh", "-i"], folder: folder, environment: ["HOME": folder.path, "PATH": "/usr/bin:/bin", "PS1": "pane> "])
    let pane = SessionPaneController(start: .runningSession(try #require(UUID(uuidString: identifier))), socket: try SocketLocation(path: process.socketPath))
    let host = RecordingHost()
    pane.delegate = host
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    window.contentView?.addSubview(other)
    pane.paneView.frame = NSRect(x: 240, y: 0, width: 660, height: 500)
    window.contentView?.addSubview(pane.paneView)
    window.makeFirstResponder(focusesPane ? pane.paneView : other)
    pane.attach()
    await waitOnMainThread { pane.terminalView?.screenText.contains("pane>") == true }
    try #require(pane.terminalView?.screenText.contains("pane>") == true)
    return HostedPane(pane: pane, host: host, window: window, identifier: identifier)
}

/// Runs `body` with a session process and a folder for its sessions.
@MainActor
func withSessionProcess(_ body: (RunningSessionProcess, URL) async throws -> Void) async throws {
    let folder = try RunningSessionProcess.makeDirectory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let process = try RunningSessionProcess()
    defer { process.stop() }
    try await body(process, folder)
}
