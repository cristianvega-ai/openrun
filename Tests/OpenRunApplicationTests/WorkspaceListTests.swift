import AppKit
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct WorkspaceListTests {
    @Test func theSessionsShowAsRowsAndTheSelectedRowAttaches() async throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.start()
        let first = try test.createShell(), second = try test.createShell()
        // The newest session is the first row.
        #expect(await waitUntil { test.shownRows == [second, first] })
        #expect(workspace.shownSession == nil && workspace.window.sessionsList.selection == nil)

        workspace.sessionsList(workspace.window.sessionsList, didSelect: first)
        #expect(await waitUntil { workspace.panes.existing(first)?.terminalView != nil })
        #expect(workspace.shownSession == first && workspace.window.sessionsList.selection == first)
        #expect(workspace.layout.selectedRow == first)

        _ = try test.process.runCommand(["rename", SessionSummary.text(for: first), "Build"])
        #expect(await waitUntil { test.rowTitles.contains("Build") })
    }

    @Test func theNeighborTakesTheSelectionWhenTheSelectedSessionEnds() async throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.start()
        let sessions = [try test.createShell(), try test.createShell(), try test.createShell()]
        #expect(await waitUntil { test.shownRows.count == 3 })
        workspace.sessionsList(workspace.window.sessionsList, didSelect: sessions[1])
        #expect(await waitUntil { workspace.panes.existing(sessions[1])?.terminalView != nil })
        _ = try test.process.runCommand(["kill", SessionSummary.text(for: sessions[1])])
        // The rows are newest first, so the row after the ended one is the oldest session.
        #expect(await waitUntil { workspace.shownSession == sessions[0] })
        #expect(test.shownRows == [sessions[2], sessions[0]] && workspace.panes.existing(sessions[1]) == nil)
        #expect(workspace.window.sessionsList.selection == sessions[0])
    }

    @Test func theKeptLayoutComesBackAtTheNextStart() async throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        test.workspace.start()
        let first = try test.createShell(), second = try test.createShell()
        #expect(await waitUntil { test.shownRows.count == 2 })
        test.workspace.sessionsList(test.workspace.window.sessionsList, didSelect: first)
        test.workspace.stop()
        test.workspace.window.window.close()

        let again = Workspace(socket: test.workspace.socket, defaults: test.defaults, frameName: nil)
        defer { again.stop(); again.window.window.close() }
        #expect(again.layout.selectedRow == first && again.layout.rows.map(\.identifier) == [second, first])
        again.start()
        #expect(await waitUntil { again.shownSession == first && again.panes.existing(first)?.terminalView != nil })
    }
}
