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
}
