import AgentConversation
import AgentThreads
import ClaudeCodeAgent
import DataStorage
import Foundation
import SessionProcessHarness
import Settings
import Testing
@testable import SessionProcess

/// The change of the model and the permission mode of a thread (proposal 9).
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

    @Test func aThreadTakesAModelAndAModeUpToTheOneOfTheSetting() async throws {
        let fixture = try await Fixture()
        let (registry, thread) = (fixture.registry, fixture.thread)
        let first = try #require(await registry.summary(thread))
        #expect(first.models == ["fable", "opus", "sonnet", "haiku"] && first.permissionModes == ["plan", "dontAsk", "default"])
        try await registry.change(thread, model: "claude-sonnet-5-5", permissionMode: "plan")
        let changed = try #require(await registry.summary(thread))
        #expect(changed.model == "claude-sonnet-5-5" && changed.permissionMode == "plan" && changed.models?.last == "claude-sonnet-5-5")
        #expect(try fixture.store.load().list.thread(thread)?.permissionMode == "plan")
        // The user leaves plan mode in the chat, up to the mode of the setting.
        try await registry.change(thread, model: nil, permissionMode: "default")
        #expect(await registry.summary(thread)?.permissionMode == "default")

        let refusal = ThreadRequestError.permissionModeNotOffered(offered: ["plan", "dontAsk", "default"])
        await #expect(throws: refusal) { try await registry.change(thread, model: nil, permissionMode: "acceptEdits") }
        await #expect(throws: refusal) { try await registry.change(thread, model: nil, permissionMode: "bypassPermissions") }
        await #expect(throws: refusal) { try await registry.create(agent: "claude-code", folder: fixture.folder.path, model: nil, permissionMode: "auto", name: nil) }
        await #expect(throws: ThreadListError.invalidModel) { try await registry.change(thread, model: "--flag", permissionMode: nil) }
        #expect(await registry.summary(thread)?.permissionMode == "default")
        #expect(refusal.description.hasPrefix("A thread can take these permission modes: plan, dontAsk, default. The setting claude-code-permission-mode"))
        await fixture.end()
    }
}
