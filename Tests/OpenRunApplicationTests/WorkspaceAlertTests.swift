import AlertNotifications
import AppKit
import SessionProcessHarness
import SessionProtocol
import Testing
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct WorkspaceAlertTests {
    /// A started workspace with two shells, the older one shown, and the badge recorded.
    private func start() async throws -> (test: TestWorkspace, shown: UUID, other: UUID, badges: () -> [Int]) {
        let test = try TestWorkspace()
        var badges: [Int] = []
        test.workspace.setBadge = { badges.append($0) }
        test.workspace.start()
        let shown = try test.createShell(), other = try test.createShell()
        #expect(await waitUntil { test.shownRows == [other, shown] })
        test.workspace.select(row: shown)
        #expect(await waitUntil { test.workspace.panes.existing(shown)?.terminalView != nil })
        return (test, shown, other, { badges })
    }

    private func notify(_ test: TestWorkspace, _ session: UUID, _ text: String) throws {
        #expect(try test.process.runCommand(["notify", "--session", SessionSummary.text(for: session), text]).status == 0)
    }

    private func alert(_ test: TestWorkspace, of session: UUID) -> String? {
        test.workspace.window.sessionsList.content.rows.first { $0.identifier == session }?.alert
    }

    @Test func anAlertOfASessionOutOfViewNotifiesAndCountsUntilTheUserSelectsIt() async throws {
        let (test, _, other, badges) = try await start()
        defer { test.stop() }
        let workspace = test.workspace, name = SessionSummary.text(for: other)
        try notify(test, other, "Allow the edit?")
        #expect(await waitUntil { alert(test, of: other) == "Allow the edit?" })
        // The title is the program with its folder. `/bin/sh` runs as `sh` or as `bash`.
        #expect(test.notifier.posted.map(\.identifier) == [name] && test.notifier.posted.first?.body == "Allow the edit?")
        #expect(test.notifier.posted.first?.title.hasSuffix("sh — \(test.process.directory.lastPathComponent)") == true)
        #expect(badges() == [1] && workspace.window.projectsList.content.needsYouCount == 1)

        workspace.sessionsList(workspace.window.sessionsList, didSelect: other)
        #expect(await waitUntil { alert(test, of: other) == nil && badges() == [1, 0] })
        #expect(test.notifier.removed == [name] && workspace.connection.overview.session(other)?.alert == nil)
    }

    @Test func theSessionInViewGetsNoMarkAndNoNotification() async throws {
        let (test, shown, _, badges) = try await start()
        defer { test.stop() }
        let workspace = test.workspace
        workspace.mainWindowContentDidBecomeActive(workspace.window)
        try notify(test, shown, "Done")
        // The session process raises the alert, and the app ends it at once.
        #expect(await waitUntil { workspace.clearedAlerts[shown] != nil && workspace.connection.overview.session(shown)?.alert == nil })
        #expect(test.notifier.posted.isEmpty && badges().isEmpty && alert(test, of: shown) == nil)
    }

    @Test func theSettingTurnsTheNotificationsOffAndTheCountStays() async throws {
        let (test, _, other, badges) = try await start()
        defer { test.stop() }
        _ = try test.process.runCommand(["settings", "set", "notifications", "off"])
        #expect(await waitUntil { !test.workspace.settings.showsNotifications })
        try notify(test, other, "Done")
        #expect(await waitUntil { badges() == [1] })
        #expect(test.notifier.posted.isEmpty)
    }

    @Test func anOpenedNotificationSelectsTheRowOfItsSession() async throws {
        let (test, _, other, _) = try await start()
        defer { test.stop() }
        try notify(test, other, "Done")
        #expect(await waitUntil { test.notifier.posted.count == 1 })
        test.notifier.opened?(test.notifier.posted[0].identifier)
        #expect(test.workspace.layout.selectedRow == other && test.workspace.shownSession == other)
        test.notifier.opened?("not a session")
        #expect(test.workspace.layout.selectedRow == other)
    }
}
