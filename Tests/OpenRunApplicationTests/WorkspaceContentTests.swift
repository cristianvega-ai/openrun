import AppKit
import SessionProcessHarness
import SessionProtocol
@testable import SessionOverview
@testable import TerminalView
import Testing
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct WorkspaceContentTests {
    /// A started workspace with one shell, selected and attached.
    private func startWithShell() async throws -> (test: TestWorkspace, shell: UUID) {
        let test = try TestWorkspace()
        test.workspace.start()
        let shell = try test.createShell()
        #expect(await waitUntil { test.shownRows == [shell] })
        test.workspace.select(row: shell)
        #expect(await waitUntil { test.workspace.panes.existing(shell)?.terminalView?.screenText.contains("test>") == true })
        return (test, shell)
    }

    @Test func aProgramThatEndsLeavesNoNoticeAndItsNeighborShows() async throws {
        let (test, shell) = try await startWithShell()
        defer { test.stop() }
        let workspace = test.workspace
        let other = try test.createShell()
        #expect(await waitUntil { test.shownRows == [other, shell] })
        var failures = 0
        workspace.showFailure = { _, _ in failures += 1 }
        let pane = try #require(workspace.panes.existing(shell)), view = try #require(pane.terminalView)
        pane.terminalView(view, send: Array("exit\r".utf8))
        #expect(await waitUntil { workspace.shownSession == other && test.shownRows == [other] })
        #expect(failures == 0 && workspace.exitedSessions.isEmpty && workspace.lostSessions.isEmpty)
    }

    @Test func aSessionThatLostItsConnectionGetsANoticeWithAWayBack() async throws {
        let (test, shell) = try await startWithShell()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.lostSessions.insert(shell)
        workspace.sessionEnded(shell)
        workspace.lostSessions.insert(shell)
        workspace.refresh()
        #expect(workspace.shown == .notice(.lostSession) && workspace.panes.existing(shell) == nil)
        let notice = try #require(workspace.window.window.contentView?.firstDescendant(PaneNoticeView.self))
        #expect(notice.button.title == "Connect Again" && !notice.button.isHidden)
        // `performClick` runs a loop of its own, which ends the test process later.
        _ = (notice.button.target as? NSObject)?.perform(notice.button.action, with: notice.button)
        #expect(workspace.shown == .session(shell))
        #expect(await waitUntil { workspace.panes.existing(shell)?.terminalView != nil })
    }

    @Test func theWindowSaysWhenItDoesNotHearTheSessionProcess() async throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.connection.firstRetryDelay = .seconds(60)
        workspace.start()
        #expect(await waitUntil { workspace.connection.status == .connected })
        #expect(workspace.shown == .nothing)
        test.process.send(signal: SIGKILL)
        #expect(await waitUntil { workspace.connection.status != .connected })
        guard case .notice(let notice) = workspace.shown else { Issue.record("\(workspace.shown)"); return }
        #expect(notice.title == "No Connection to the Session Process" && notice.buttonTitle == nil)
        #expect(notice.message.hasSuffix("OpenRun tries again by itself."))
    }
}

extension NSView {
    /// The first view of a type below this view.
    func firstDescendant<View: NSView>(_ type: View.Type) -> View? {
        for subview in subviews {
            if let match = subview as? View ?? subview.firstDescendant(type) { return match }
        }
        return nil
    }
}

extension TerminalView {
    /// The text on the screen of the view.
    var screenText: String { String(decoding: (try? terminal.formatted(.plainText)) ?? [], as: UTF8.self) }
}
