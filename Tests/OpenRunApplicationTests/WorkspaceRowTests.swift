import AppKit
import SessionProcessHarness
import SessionProtocol
import SessionsList
import Testing
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct WorkspaceRowTests {
    @Test func aCloseAsksOnlyWhileAProgramOtherThanAShellRuns() async throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.start()
        var questions: [CloseQuestion] = [], agrees = false
        workspace.confirmClose = { question, answer in
            questions.append(question)
            answer(agrees)
        }
        let shell = try test.createShell()
        let sleeper = try #require(UUID(uuidString: try test.process.createSession(program: ["/bin/sleep", "600"])))
        #expect(await waitUntil { workspace.connection.overview.session(sleeper)?.foregroundProgram == "sleep" && test.shownRows.count == 2 })

        workspace.sessionsList(workspace.window.sessionsList, didClose: shell)
        #expect(await waitUntil { test.shownRows == [sleeper] })
        #expect(questions.isEmpty)

        workspace.closeRow(sleeper)
        #expect(questions.map(\.program) == ["sleep"])
        try await Task.sleep(for: .milliseconds(300))
        #expect(test.shownRows == [sleeper])
        agrees = true
        workspace.closeRow(sleeper)
        #expect(await waitUntil { test.shownRows.isEmpty })
        #expect(questions.count == 2)
    }

    @Test func aNameAMoveAndTheFilterReachTheSessionProcessAndTheLayout() async throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        let workspace = test.workspace, list = workspace.window.sessionsList
        workspace.start()
        let sessions = [try test.createShell(), try test.createShell(), try test.createShell()]
        #expect(await waitUntil { test.shownRows == sessions.reversed() })

        workspace.sessionsList(list, didRename: sessions[0], to: "Server")
        #expect(await waitUntil { test.rowTitles.last == "Server" })
        #expect(try test.process.runCommand(["list", "--json"]).standardOutput.contains("\"name\" : \"Server\""))

        workspace.sessionsList(list, didMove: sessions[0], toIndex: 0)
        #expect(test.shownRows == [sessions[0], sessions[2], sessions[1]])
        workspace.sessionsList(list, didChange: .finished, order: .name)
        #expect(workspace.layout.filter == "finished" && workspace.layout.order == "name")
        workspace.stop()
        #expect(workspace.layoutStore.load().rows.map(\.identifier) == [sessions[0], sessions[2], sessions[1]])
        #expect(workspace.layoutStore.load().order == "name")
    }

    @Test func theNextAndThePreviousRowGoAroundTheList() async throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.start()
        let first = try test.createShell(), second = try test.createShell()
        #expect(await waitUntil { test.shownRows == [second, first] })
        workspace.moveSelection(by: 1)
        #expect(workspace.layout.selectedRow == second && workspace.shownSession == second)
        workspace.moveSelection(by: 1)
        workspace.moveSelection(by: 1)
        #expect(workspace.layout.selectedRow == second)
        workspace.moveSelection(by: -1)
        #expect(workspace.layout.selectedRow == first && workspace.window.sessionsList.selection == first)
    }
}
