import AgentThreads
import DataStorage
import Foundation
import SessionProcessHarness
import Settings
import Testing
@testable import SessionProcess

@Suite struct ThreadAccountTests {
    @Test func aNewThreadTakesAnAccountOfItsAgentByTheName() async throws {
        let folder = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var settings = SettingValues()
        try settings.change(.claudeCodeAccounts, to: #"[{"name":"Work","folder":"/config/claude-work"}]"#, requestedBy: .application)
        let store = ThreadStore(dataFolder: DataFolder(path: folder.path))
        let registry = ThreadRegistry(store: store, accountChoices: ThreadAccountChoices(settings)) { FakeAgentSettings.make() }
        let thread = try await registry.create(agent: "claude-code", folder: folder.path, model: nil, permissionMode: nil, name: nil, account: "work")
        let kept = try store.load().list.thread(thread.identifier)?.account
        #expect(thread.accountName == "Work" && kept == ThreadAccount(name: "Work", settingsFolder: "/config/claude-work"))
        // A thread that names no account runs under the account of the login shell.
        let plain = try await registry.create(agent: "claude-code", folder: folder.path, model: nil, permissionMode: nil, name: nil)
        #expect(plain.accountName == nil)
        // An account of Claude Code is no account of Codex.
        await #expect(throws: ThreadRequestError.unknownAccount) {
            try await registry.create(agent: "codex", folder: folder.path, model: nil, permissionMode: nil, name: nil, account: "Work")
        }
        // The thread shows the new name of its account, and its record keeps the folder that selects the account.
        try settings.change(.claudeCodeAccounts, to: #"[{"name":"Office","folder":"/config/claude-work"}]"#, requestedBy: .application)
        await registry.updateSettings(model: "opus", permissionMode: "default", processLimit: 8, accountChoices: ThreadAccountChoices(settings), version: 1)
        let renamed = await registry.summary(thread.identifier)?.accountName
        let loaded = await ThreadRegistry(store: store, accountChoices: ThreadAccountChoices(settings)) { FakeAgentSettings.make() }.allSummaries.first?.accountName
        #expect(renamed == "Office" && loaded == "Office")
        // The thread keeps the account that the settings lose, because a resume runs under the same account.
        await registry.updateSettings(model: "opus", permissionMode: "default", processLimit: 8, accountChoices: ThreadAccountChoices(), version: 2)
        let later = await registry.summary(thread.identifier)?.accountName
        #expect(later == "Work")
        await #expect(throws: ThreadRequestError.unknownAccount) {
            try await registry.create(agent: "claude-code", folder: folder.path, model: nil, permissionMode: nil, name: nil, account: "Work")
        }
    }
}
