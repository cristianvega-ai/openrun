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
    }
}
