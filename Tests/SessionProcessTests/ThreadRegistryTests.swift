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
            feed.addWatcher(ObjectIdentifier(key)) { [self] message in messages.withLock { $0.append(message) } }
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
}
