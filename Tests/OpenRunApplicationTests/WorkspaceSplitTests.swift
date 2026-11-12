import AppKit
import PseudoTerminal
import SessionProcessHarness
import SessionProtocol
import Testing
import WindowLayout
@testable import OpenRunApplication

/// The splits of the third pane, on a real session process.
@MainActor @Suite(.serialized) struct WorkspaceSplitTests {
    /// A started workspace with one shell in the third pane.
    private func start() async throws -> (test: TestWorkspace, first: UUID) {
        let test = try TestWorkspace()
        let folder = test.process.directory.path
        (test.workspace.home, test.workspace.loginShell) = (folder, LoginShell(path: "/bin/sh"))
        test.workspace.sessionEnvironment = ["HOME": folder, "PATH": "/usr/bin:/bin", "PS1": "test> "]
        test.workspace.start()
        #expect(await waitUntil { test.workspace.connection.hasSessionList })
        test.workspace.newSession()
        #expect(await waitUntil { test.workspace.shownSession.flatMap { test.workspace.panes.existing($0)?.terminalView } != nil })
        return (test, try #require(test.workspace.shownSession))
    }

    private func item(_ action: Selector) -> NSMenuItem { NSMenuItem(title: "", action: action, keyEquivalent: "") }

    @Test func aSplitStartsAShellBesideThePaneInTheSameRow() async throws {
        let (test, first) = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        #expect(workspace.validateMenuItem(item(#selector(Workspace.splitRight(_:)))) && !workspace.validateMenuItem(item(#selector(Workspace.selectNextPane(_:)))))
        workspace.splitRight(nil)
        #expect(await waitUntil { workspace.connection.overview.sessions.count == 2 && workspace.splitView != nil })
        let second = try #require(workspace.connection.overview.sessions.map(\.identifier).first { $0 != first })
        // The row keeps its place and its name, and the new session has no row of its own.
        #expect(test.shownRows == [first] && workspace.layout.rows.first?.pane.leaves == [first, second])
        #expect(workspace.shown == .split(row: first, pane: .split(LayoutSplit(direction: .sideBySide, first: .session(first), second: .session(second)))))
        // The new pane has the keyboard focus, and both panes are attached.
        #expect(await waitUntil { workspace.panes.existing(second)?.terminalView != nil && workspace.focusedLeaf == second })
        let (left, right) = (try #require(workspace.splitView?.view(of: first)), try #require(workspace.splitView?.view(of: second)))
        #expect(left.frame.width > 100 && right.frame.minX > left.frame.maxX - 1 && workspace.validateMenuItem(item(#selector(Workspace.selectNextPane(_:)))))
        // The pane that the row showed alone has its place in the split.
        #expect(left.window === workspace.window.window && right.window === workspace.window.window)

        workspace.selectNextPane(nil)
        #expect(workspace.focusedLeaf == first)
        workspace.splitDown(nil)
        #expect(await waitUntil { workspace.layout.rows.first?.pane.leaves.count == 3 })
        #expect(workspace.layout.rows.count == 1 && workspace.layout.rows.first?.pane.leaves.first == first)
    }

    @Test func aRowWithSplitsOfTheLayoutShowsEachOfItsSessionsAtTheStart() async throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        let workspace = test.workspace
        let (first, second) = (try test.createShell(), try test.createShell())
        workspace.layout.follow(sessions: [first, second])
        workspace.layout.split(first, with: second, direction: .stacked)
        workspace.layout.selectedRow = first
        workspace.start()
        #expect(await waitUntil { workspace.panes.existing(first)?.terminalView != nil && workspace.panes.existing(second)?.terminalView != nil })
        for session in [first, second] {
            let view = try #require(workspace.panes.existing(session)?.terminalView)
            #expect(view.window === workspace.window.window && view.frame.height > 50 && view.frame.width > 50)
            #expect(workspace.splitView?.leaf(holding: view) == session)
        }
        #expect(test.shownRows == [first])
    }

    @Test func commandWClosesThePaneWithTheFocusAndTheOtherHalfTakesTheRoom() async throws {
        let (test, first) = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.confirmClose = { _, answer in answer(true) }
        workspace.splitDown(nil)
        #expect(await waitUntil { workspace.splitView != nil && workspace.focusedLeaf != first })
        let second = try #require(workspace.focusedLeaf)
        // A divider that the user moved stays in the layout.
        workspace.splitView?.fractionChanged?(second, 0.7)
        guard case .split(let split) = workspace.layout.rows.first?.pane else { Issue.record("no split"); return }
        #expect(split.fraction == 0.7 && split.direction == .stacked)
        workspace.closeSession(nil)
        #expect(await waitUntil { workspace.shown == .session(first) })
        #expect(workspace.connection.overview.sessions.map(\.identifier) == [first] && workspace.splitView == nil && test.shownRows == [first])
    }
}
