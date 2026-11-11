import AppKit
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import MainWindow
@testable import OpenRunApplication
@testable import TerminalView

@MainActor @Suite(.serialized) struct WorkspacePaneTests {
    /// A started workspace with two shells. The older one is selected and attached.
    private func startWithTwoShells() async throws -> (test: TestWorkspace, shown: UUID, other: UUID) {
        let test = try TestWorkspace()
        test.workspace.start()
        let shown = try test.createShell(), other = try test.createShell()
        #expect(await waitUntil { test.shownRows == [other, shown] })
        test.workspace.select(row: shown)
        #expect(await waitUntil { test.workspace.panes.existing(shown)?.terminalView?.screenText.contains("test>") == true })
        return (test, shown, other)
    }

    @Test func theThirdPaneShowsTheTitleOfTheShownSessionOnly() async throws {
        let (test, shown, other) = try await startWithTwoShells()
        defer { test.stop() }
        let workspace = test.workspace, title = workspace.window.contentPane.titleLabel
        let pane = try #require(workspace.panes.existing(shown)), view = try #require(pane.terminalView)
        pane.terminalView(view, send: Array("printf '\\033]2;Build log\\007'\r".utf8))
        #expect(await waitUntil { title.stringValue == "Build log" })
        workspace.select(row: other)
        #expect(await waitUntil { workspace.panes.existing(other)?.terminalView != nil })
        let otherTitle = title.stringValue
        #expect(otherTitle != "Build log")
        // The pane that the window does not show stays attached, and its title does not reach the window.
        pane.terminalView(view, send: Array("printf '\\033]2;Hidden\\007'\r".utf8))
        #expect(await waitUntil { pane.title == "Hidden" })
        #expect(title.stringValue == otherTitle)
    }

    @Test func aChangeOfASettingReachesEachPaneAtOnce() async throws {
        let (test, shown, other) = try await startWithTwoShells()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.select(row: other)
        #expect(await waitUntil { workspace.panes.existing(other)?.terminalView != nil })
        _ = try test.process.runCommand(["settings", "set", "font-size", "19"])
        _ = try test.process.runCommand(["settings", "set", "option-as-alt", "both"])
        #expect(await waitUntil { workspace.settings.optionAsAlt == .both })
        for session in [shown, other] {
            let view = try #require(workspace.panes.existing(session)?.terminalView)
            #expect(view.standardFontSize == 19 && view.optionKeyRule == .both)
        }
        // A pane that attaches later starts with the settings.
        let later = try test.createShell()
        #expect(await waitUntil { test.shownRows.count == 3 })
        workspace.select(row: later)
        #expect(await waitUntil { workspace.panes.existing(later)?.terminalView != nil })
        #expect(workspace.panes.existing(later)?.terminalView?.standardFontSize == 19)
    }

    @Test func aCloseOfTheWindowLeavesTheSessionsAndTheNextShowAttachesAgain() async throws {
        let (test, shown, other) = try await startWithTwoShells()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.window.window.close()
        #expect(workspace.panes.all.isEmpty && workspace.shown == .nothing)
        #expect(try Set(test.process.listedIdentifiers()) == Set([shown, other].map(SessionSummary.text)))
        workspace.showWindow()
        #expect(workspace.shown == .session(shown))
        #expect(await waitUntil { workspace.panes.existing(shown)?.terminalView?.screenText.contains("test>") == true })
    }
}
