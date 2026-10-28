import AppKit
import SessionProtocol
import SessionWindow
import Testing
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct MainMenuTests {
    @Test func aWindowControllerStaysUntilItsWindowCloses() throws {
        _ = NSApplication.shared
        let windows = WindowList(socket: try SocketLocation(path: "/tmp/openrun-app-test.socket"))
        windows.open(.runningSession(UUID()))
        let controller = try #require(windows.controllers.first)
        #expect(windows.controllers.count == 1)
        controller.window.close()
        #expect(windows.controllers.isEmpty)
    }

    @Test func theStandardNewSessionUsesTheHomeFolder() {
        guard case .newSession(let folder, let environment) = SessionStart.newSessionInHomeFolder() else {
            Issue.record("Expected a new session")
            return
        }
        #expect(folder == NSHomeDirectory())
        #expect(environment["PATH"] == ProcessInfo.processInfo.environment["PATH"])
    }
}
