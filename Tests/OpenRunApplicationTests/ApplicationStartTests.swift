import AppKit
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import OpenRunApplication

/// The app at its start, with a real session process.
@MainActor @Suite(.serialized) struct ApplicationStartTests {
    private let launch = Notification(name: NSApplication.didFinishLaunchingNotification)
    private let quit = Notification(name: NSApplication.willTerminateNotification)

    /// An application on the session process of a test workspace.
    private func makeApplication(_ test: TestWorkspace) -> OpenRunApplication {
        // An empty start file keeps the login shell of the first session quiet.
        FileManager.default.createFile(atPath: test.process.directory.appendingPathComponent(".zshrc").path, contents: Data())
        return OpenRunApplication(socket: test.workspace.socket, workspace: test.workspace)
    }

    @Test func theStartShowsTheWindowAndOneShellAndACloseLeavesTheSession() async throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        let application = makeApplication(test), workspace = test.workspace
        application.applicationDidFinishLaunching(launch)
        #expect(workspace.window.window.isVisible)
        #expect(await waitUntil { workspace.shownSession.flatMap { workspace.panes.existing($0)?.terminalView } != nil })
        let first = try test.process.listedIdentifiers()
        #expect(first.count == 1 && workspace.connection.overview.sessions.first?.folder == workspace.home)

        workspace.window.window.close()
        #expect(try test.process.listedIdentifiers() == first && workspace.panes.all.isEmpty)
        #expect(application.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
        #expect(workspace.window.window.isVisible)
        #expect(await waitUntil { workspace.shownSession.flatMap { workspace.panes.existing($0)?.terminalView } != nil })
        application.applicationWillTerminate(quit)
        #expect(try test.process.listedIdentifiers() == first && workspace.panes.all.isEmpty)
        #expect(!application.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @Test func theStartOpensNoShellWhenASessionRuns() async throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        let running = try test.createShell()
        let application = makeApplication(test)
        application.applicationDidFinishLaunching(launch)
        #expect(await waitUntil { test.shownRows == [running] })
        try await Task.sleep(for: .milliseconds(300))
        #expect(try test.process.listedIdentifiers().count == 1 && !test.workspace.opensFirstSession)
    }
}
