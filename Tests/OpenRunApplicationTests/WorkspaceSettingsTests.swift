import AppKit
import SessionProcessHarness
import Testing
@testable import OpenRunApplication

/// The settings window on a real session process.
@MainActor @Suite(.serialized) struct WorkspaceSettingsTests {
    @Test func theSettingsWindowChangesASettingAndTellsARefusal() async throws {
        let test = try TestWorkspace()
        defer { test.stop() }
        let workspace = test.workspace
        var failures: [String] = []
        workspace.showSettingFailure = { failures.append($0) }
        let item = NSMenuItem(title: "Settings…", action: #selector(Workspace.showSettings(_:)), keyEquivalent: ",")
        // The window shows the values of the session process, so it waits for them.
        #expect(!workspace.validateMenuItem(item))
        workspace.start()
        #expect(await waitUntil { workspace.validateMenuItem(item) })
        workspace.showSettings(nil)
        let settings = try #require(workspace.settingsWindow)
        defer { settings.close() }
        #expect(settings.window?.isVisible == true)

        settings.change?("font-size", "15")
        #expect(await waitUntil { workspace.settings.fontSize == 15 })
        #expect(try test.process.runCommand(["settings", "get", "font-size"]).standardOutput == "15\n")
        // This test process is not OpenRun.app, so the session process refuses a protected setting.
        settings.change?("session-limit", "5")
        #expect(await waitUntil { failures.count == 1 })
        #expect(failures == ["The setting session-limit is protected. Change it in the settings window of OpenRun."])
        #expect(workspace.settings.sessionLimit == 100)
        // A second call shows the same window.
        workspace.showSettings(nil)
        #expect(workspace.settingsWindow === settings)
        // The menu of the new-session button opens the same window at the accounts.
        workspace.sessionsListDidRequestAccounts(workspace.window.sessionsList)
        #expect(workspace.settingsWindow === settings && settings.window?.isVisible == true)
        // Command-W in the settings window closes that window, and the terminal of the main window stays.
        let shell = try test.createShell()
        #expect(await waitUntil { test.shownRows == [shell] })
        let close = NSMenuItem(title: "", action: #selector(Workspace.closeSession(_:)), keyEquivalent: "w")
        // The main window of this test does not show, so its own item is off.
        #expect(!workspace.validateMenuItem(close) && close.title == "Close Terminal")
        workspace.keyWindow = { settings.window }
        #expect(workspace.validateMenuItem(close) && close.title == "Close Window")
        workspace.closeSession(nil)
        #expect(settings.window?.isVisible == false && test.shownRows == [shell] && workspace.connection.overview.sessions.count == 1)
    }
}
