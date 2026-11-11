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
        await #expect(throws: ThreadRequestError.unsupportedAgent("codex")) { try await registry.create(agent: "codex", folder: folder, model: nil, permissionMode: nil, name: nil) }
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
        await registry.updateProjects(projects)
        #expect(await registry.summary(thread.identifier)?.projectIdentifier == project.identifier)
        #expect(fixture.changed.last?.projectIdentifier == project.identifier)
    }
}
