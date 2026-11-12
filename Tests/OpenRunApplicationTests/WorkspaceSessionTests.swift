import AppKit
import PseudoTerminal
import SessionProcessHarness
import SessionProtocol
import SessionsList
import Testing
@testable import OpenRunApplication
@testable import TerminalView

@MainActor @Suite(.serialized) struct WorkspaceSessionTests {
    /// A started workspace whose new sessions read no start file of the user.
    private func start() async throws -> TestWorkspace {
        let test = try TestWorkspace()
        let folder = test.process.directory.path
        test.workspace.home = folder
        test.workspace.loginShell = LoginShell(path: "/bin/sh")
        test.workspace.sessionEnvironment = ["HOME": folder, "PATH": "/usr/bin:/bin", "PS1": "test> "]
        test.workspace.start()
        #expect(await waitUntil { test.workspace.connection.hasSessionList })
        return test
    }

    @Test func commandKClearsTheScrollbackOfTheShownSession() async throws {
        let test = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        let item = NSMenuItem(title: "Clear", action: #selector(Workspace.clearSession(_:)), keyEquivalent: "k")
        #expect(!workspace.validateMenuItem(item))
        workspace.newSession()
        #expect(await waitUntil { workspace.shownSession.flatMap { workspace.panes.existing($0)?.terminalView } != nil })
        let session = try #require(workspace.shownSession), view = try #require(workspace.panes.existing(session)?.terminalView)
        _ = try test.process.runCommand(["send", SessionSummary.text(for: session), "--enter", "seq 1 300"])
        #expect(await waitUntil { view.terminal.scrollbackLineCount > 200 })
        #expect(workspace.validateMenuItem(item))
        workspace.clearSession(nil)
        // The clear comes back as output, so the copy of the view loses its scrollback too.
        #expect(await waitUntil { view.terminal.scrollbackLineCount == 0 })
    }

    @Test func aNewSessionStartsInTheHomeFolderAndTakesTheSelectionAndTheFocus() async throws {
        let test = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.newSession()
        #expect(await waitUntil { workspace.shownSession.flatMap { workspace.panes.existing($0)?.terminalView } != nil })
        let session = try #require(workspace.connection.overview.sessions.first)
        #expect(session.folder == workspace.home && workspace.layout.selectedRow == session.identifier)
        #expect(workspace.window.window.firstResponder === workspace.panes.existing(session.identifier)?.terminalView)
    }

    @Test func aCommandOfTheSettingsRunsInANewTerminal() async throws {
        let test = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        _ = try test.process.runCommand(["settings", "set", "new-session-commands", #"[{"name":"Sleeper","command":"sleep 600"}]"#])
        #expect(await waitUntil { workspace.window.sessionsList.content.terminalCommands == ["Sleeper"] })
        workspace.sessionsList(workspace.window.sessionsList, didRequest: .terminal(command: "Sleeper"))
        #expect(await waitUntil { workspace.connection.overview.sessions.first?.foregroundProgram == "sleep" })
        #expect(workspace.connection.overview.sessions.first?.command == ["/bin/sh", "-l", "-i", "-c", "exec sleep 600"])
    }

    @Test func aFailedStartShowsTheReason() async throws {
        let test = try await start()
        defer { test.stop() }
        var failures: [String] = []
        test.workspace.showFailure = { title, message in failures.append(title + ": " + message) }
        test.workspace.home = "/no/such/folder"
        test.workspace.newSession()
        #expect(await waitUntil { failures.count == 1 })
        #expect(failures.first?.hasPrefix("The session could not start: ") == true && test.shownRows.isEmpty)
    }
}
