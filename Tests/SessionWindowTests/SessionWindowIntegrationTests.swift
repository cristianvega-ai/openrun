import AppKit
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import SessionWindow
@testable import TerminalView

@MainActor @Suite(.serialized) struct SessionWindowIntegrationTests {
    @Test func aWindowUsesASessionAndTheSessionOutlivesItsClose() async throws {
        _ = NSApplication.shared
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let process = try RunningSessionProcess()
        defer { process.stop() }
        let identifier = try process.createSession(program: ["/bin/sh", "-i"], folder: folder, environment: ["HOME": folder.path, "PATH": "/usr/bin:/bin", "PS1": "openrun> "])
        let session = try #require(UUID(uuidString: identifier))
        let location = try SocketLocation(path: process.socketPath)
        let first = SessionWindowController(start: .runningSession(session), socket: location)
        first.showWindow()
        defer { first.window.close() }
        await waitOnMainThread { first.view != nil }
        let firstView = try #require(first.view)
        first.terminalView(firstView, send: Array("printf '%s%s\\n' 'ready-' '42'\r".utf8))
        await waitOnMainThread { firstView.screenText.contains("ready-42") }
        #expect(firstView.screenText.contains("ready-42"))
        #expect(try process.screenText(of: identifier).contains("ready-42"))
        first.window.close()
        #expect(try process.listedIdentifiers() == [identifier])
        let second = SessionWindowController(start: .runningSession(session), socket: location)
        second.showWindow()
        defer { second.window.close() }
        await waitOnMainThread { second.view != nil }
        let secondView = try #require(second.view)
        #expect(secondView.screenText.contains("ready-42"))
        second.terminalView(secondView, send: Array("exit\r".utf8))
        await waitOnMainThread { !second.window.isVisible }
        #expect(!second.window.isVisible)
        await waitOnMainThread { (try? process.listedIdentifiers().isEmpty) == true }
        #expect(try process.listedIdentifiers().isEmpty)
    }
}
