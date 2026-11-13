import AgentThreads
import DataStorage
import Foundation
import Projects
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing
@testable import SessionProcess

@Suite struct ThreadRegistryTests {
    /// A registry on a new data folder, with a watcher of its feed.
    private final class Fixture: Sendable {
        let folder: URL
        let store: ThreadStore
        let feed = SessionChangeFeed()
        let messages = Mutex<[ServerMessage]>([])
        let registry: ThreadRegistry

        init(settings: AgentLaunchSettings = FakeAgentSettings.make()) throws {
            folder = try RunningSessionProcess.makeDirectory()
            store = ThreadStore(dataFolder: DataFolder(path: folder.path))
            registry = ThreadRegistry(store: store, changes: feed) { settings }
            let key = NSObject()
            feed.addWatcher(ObjectIdentifier(key), includesThreads: true) { [self] message in messages.withLock { $0.append(message) } }
        }

        /// The summaries that the feed sent for changes of threads.
        var changed: [ThreadSummary] {
            messages.withLock { $0 }.compactMap { if case .threadChanged(let summary) = $0 { summary } else { nil } }
        }

        func remove() { try? FileManager.default.removeItem(at: folder) }
    }

    @Test func aNewThreadIsSavedAndTheNextSessionProcessHasIt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let summary = try await fixture.registry.create(agent: "claude-code", folder: fixture.folder.path, model: nil, permissionMode: "plan", name: " Notes ")
        #expect(summary.model == "opus" && summary.permissionMode == "plan" && summary.name == "Notes" && summary.state == "idle")
        #expect(summary.folder.hasSuffix(fixture.folder.path) && summary.folder.hasPrefix("/private") && !summary.isProcessRunning)
        #expect(fixture.changed == [summary])
        let again = ThreadRegistry(store: fixture.store) { FakeAgentSettings.make() }
        #expect(await again.allSummaries == [summary])
        #expect(await !again.hasRunningProcess)
    }

    @Test func aRequestThatCannotWorkIsRefusedAndChangesNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let registry = fixture.registry, folder = fixture.folder.path
        await #expect(throws: ThreadRequestError.unsupportedAgent("gemini")) { try await registry.create(agent: "gemini", folder: folder, model: nil, permissionMode: nil, name: nil) }
        await #expect(throws: ThreadRequestError.folderDoesNotExist) { try await registry.create(agent: "claude-code", folder: folder + "/missing", model: nil, permissionMode: nil, name: nil) }
        await #expect(throws: ThreadListError.invalidModel) { try await registry.create(agent: "claude-code", folder: folder, model: "--flag", permissionMode: nil, name: nil) }
        await #expect(throws: ThreadListError.unknownThread(UUID(uuidString: "00000000-0000-4000-8000-000000000001")!)) {
            try await registry.rename(UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, to: "x")
        }
        #expect(await registry.allSummaries.isEmpty && fixture.changed.isEmpty)
        #expect(try fixture.store.load().list.threads.isEmpty)
    }

    @Test func aNameAndACloseReachTheFileAndTheFeed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let registry = fixture.registry
        let thread = try await registry.create(agent: "claude-code", folder: fixture.folder.path, model: nil, permissionMode: nil, name: nil).identifier
        try await registry.rename(thread, to: "Release")
        #expect(fixture.changed.last?.name == "Release")
        #expect(try fixture.store.load().list.thread(thread)?.name == "Release")
        try await registry.close(thread)
        #expect(await registry.allSummaries.isEmpty)
        #expect(try fixture.store.load().list.threads.isEmpty)
        #expect(fixture.messages.withLock { $0.last } == .threadEnded(identifier: thread))
        await #expect(throws: ThreadListError.unknownThread(thread)) { try await registry.runner(for: thread) }
    }

    @Test func aTurnChangesTheSummaryOnTheFeedAndTheRecordInTheFile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let registry = fixture.registry
        let thread = try await registry.create(agent: "claude-code", folder: fixture.folder.path, model: nil, permissionMode: nil, name: nil).identifier
        let runner = try await registry.runner(for: thread)
        #expect(try await registry.runner(for: thread) === runner)
        try await runner.send(text: "Reply with the single word ok.")
        #expect(await eventually { await registry.summary(thread)?.state == "finishedTurn" })
        let summary = try #require(await registry.summary(thread))
        #expect(summary.title == "Reply with the single word ok." && summary.isProcessRunning && summary.waitingMessageCount == 0)
        // The agent gave a usage reading of the account in the turn, and the summary has it with its time.
        let window = try #require(summary.usageWindows?.first)
        #expect(window.lengthInMinutes == 10_080 && window.usedFraction != nil && window.status == "allowed")
        #expect(try #require(summary.usageReadAt).timeIntervalSinceNow > -60)
        #expect(await registry.hasRunningProcess)
        #expect(fixture.changed.contains { $0.state == "inProgress" } && fixture.changed.last == summary)
        #expect(try fixture.store.load().list.thread(thread)?.hasConversation == true)
        await registry.terminateAll()
        #expect(await eventually { await !runner.isProcessRunning })
    }

    @Test func aThreadBelongsToTheProjectThatHoldsItsFolder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let registry = fixture.registry
        let thread = try await registry.create(agent: "claude-code", folder: fixture.folder.path, model: nil, permissionMode: nil, name: nil)
        #expect(thread.projectIdentifier == nil)
        var projects = ProjectList()
        let project = try projects.add(folder: fixture.folder.path, name: nil, currentFolder: nil)
        await registry.updateProjects(projects, version: 1)
        #expect(await registry.summary(thread.identifier)?.projectIdentifier == project.identifier)
        #expect(fixture.changed.last?.projectIdentifier == project.identifier)
    }

    @Test func olderSettingsCannotApplyAfterANewerUpdate() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let gate = SettingsLaunchGate()
        let registry = ThreadRegistry(store: fixture.store, processLimit: 1, defaultPermissionMode: "auto") {
            await gate.settings()
        }
        let first = try await registry.create(agent: "claude-code", folder: fixture.folder.path, model: nil, permissionMode: "auto", name: nil).identifier
        let second = try await registry.create(agent: "claude-code", folder: fixture.folder.path, model: nil, permissionMode: "auto", name: nil).identifier
        try await registry.runner(for: first).send(text: "First")
        #expect(await eventually { await registry.summary(first)?.isProcessRunning == true })
        try await registry.runner(for: second).send(text: "Second")
        #expect(await eventually { await registry.slots.waiting.contains(second) })
        let older = Task { await registry.updateSettings(model: "opus", permissionMode: "plan", processLimit: 2, version: 1) }
        #expect(await eventually { await gate.entered })
        await registry.updateSettings(model: "opus", permissionMode: "auto", processLimit: 2, version: 2)
        await gate.release()
        await older.value
        #expect(try await registry.record(first).permissionMode == "auto")
        #expect(try await registry.record(second).permissionMode == "auto")
        await registry.terminateAll()
    }

    @Test func olderProjectChangesCannotReplaceNewerChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let registry = fixture.registry
        let thread = try await registry.create(agent: "claude-code", folder: fixture.folder.path, model: nil, permissionMode: nil, name: nil).identifier
        var projects = ProjectList()
        let project = try projects.add(folder: fixture.folder.path, name: nil, currentFolder: nil)
        await registry.updateProjects(projects, version: 2)
        await registry.updateProjects(ProjectList(), version: 1)
        #expect(await registry.summary(thread)?.projectIdentifier == project.identifier)
    }

    @Test func aNewAgentIsKnownBeforeItsSummaryIsPublished() async throws {
        let fixture = try Fixture(settings: FakeAgentSettings.make(mode: "neverEnds"))
        defer { fixture.remove() }
        let registry = fixture.registry
        let thread = try await registry.create(agent: "claude-code", folder: fixture.folder.path, model: nil, permissionMode: nil, name: nil).identifier
        let runner = try await registry.runner(for: thread)
        _ = try await runner.send(text: "Work.")
        #expect(await eventually { await runner.facts.process != nil })
        let process = try #require(await runner.facts.process)
        await registry.forgetPublishedAgentsForTest()
        #expect(await registry.thread(startedProcess: process) == thread)
        #expect(await registry.isStartedByAgent(process))
        await registry.terminateAll()
    }
}

extension ThreadRegistry {
    fileprivate func forgetPublishedAgentsForTest() { agentProcesses = [:] }
}

private actor SettingsLaunchGate {
    var count = 0
    var entered = false
    var continuation: CheckedContinuation<Void, Never>?
    func settings() async -> AgentLaunchSettings {
        count += 1
        if count == 2 {
            entered = true
            await withCheckedContinuation { continuation = $0 }
        }
        return FakeAgentSettings.make(mode: "neverEnds")
    }
    func release() { continuation?.resume(); continuation = nil }
}
