import AgentConversation
import AgentThreads
import ClaudeCodeAgent
import DataStorage
import Foundation
import SessionProcessHarness
import Settings
import Testing
@testable import SessionProcess

/// The model and the permission mode of a thread, and their menus (proposal 9).
@Suite struct ThreadChangeTests {
    /// A registry on a new data folder, with one thread.
    private struct Fixture {
        let folder: URL
        let store: ThreadStore
        let registry: ThreadRegistry
        let thread: UUID

        init(environment: [String: String] = [:]) async throws {
            folder = try RunningSessionProcess.makeDirectory()
            store = ThreadStore(dataFolder: DataFolder(path: folder.path))
            let settings = FakeAgentSettings.make(environment: environment)
            registry = ThreadRegistry(store: store) { settings }
            thread = try await registry.create(agent: "claude-code", folder: folder.path, model: nil, permissionMode: nil, name: nil).identifier
        }

        func end() async {
            await registry.terminateAll()
            try? FileManager.default.removeItem(at: folder)
        }
    }

    @Test func theSettingsAndTheAgentNameTheSameModes() {
        #expect(SettingName.claudeCodePermissionModes == ClaudeCodePermissionMode.fromStrictestToWidest.map(\.rawValue))
    }

    @Test func theSummaryOfAThreadHoldsTheChoicesOfItsMenus() async throws {
        let fixture = try await Fixture()
        let (registry, thread) = (fixture.registry, fixture.thread)
        let first = try #require(await registry.summary(thread))
        #expect(first.models == ["fable", "opus", "sonnet", "haiku"] && first.permissionModes == ["plan", "dontAsk", "default"])
        // A wider setting offers more modes, and a model of the settings joins the menu.
        await registry.updateSettings(model: "claude-opus-5-5", permissionMode: "acceptEdits", processLimit: 8, version: 1)
        let wider = try #require(await registry.summary(thread))
        #expect(wider.models?.last == "claude-opus-5-5" && wider.permissionModes == ["plan", "dontAsk", "default", "acceptEdits"])
        await fixture.end()
    }
}
