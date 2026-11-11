import AgentConversation
import AgentThreads
import DataStorage
import Foundation
import SessionProcessHarness
import Testing
@testable import SessionProcess

/// The limit of the agent processes that run at one time (decision of
/// 2026-11-10). The tests use a limit of one process.
@Suite struct ThreadProcessLimitTests {
    /// A registry with a limit of one process, and two threads with their runners.
    private struct Fixture {
        let folder: URL
        let registry: ThreadRegistry
        let (first, second): (UUID, UUID)
        let (firstRunner, secondRunner): (ThreadRunner, ThreadRunner)

        init(mode: String = "replay") async throws {
            folder = try RunningSessionProcess.makeDirectory()
            let settings = FakeAgentSettings.make(mode: mode)
            registry = ThreadRegistry(store: ThreadStore(dataFolder: DataFolder(path: folder.path)), processLimit: 1) { settings }
            first = try await registry.create(agent: "claude-code", folder: folder.path, model: nil, permissionMode: nil, name: nil).identifier
            second = try await registry.create(agent: "claude-code", folder: folder.path, model: nil, permissionMode: nil, name: nil).identifier
            firstRunner = try await registry.runner(for: first)
            secondRunner = try await registry.runner(for: second)
        }

        /// Whether the agent of each thread runs, as the lists show it.
        func runs() async -> [Bool?] {
            await [registry.summary(first)?.isProcessRunning, registry.summary(second)?.isProcessRunning]
        }

        func end() async {
            await registry.terminateAll()
            try? FileManager.default.removeItem(at: folder)
        }
    }

    @Test func anAgentWithNoWorkEndsToMakeRoomForAnother() async throws {
        let fixture = try await Fixture()
        try await fixture.firstRunner.send(text: "One.")
        #expect(await eventually { await fixture.registry.summary(fixture.first)?.state == "finishedTurn" })
        #expect(await fixture.runs() == [true, false])
        try await fixture.secondRunner.send(text: "Two.")
        #expect(await eventually { await fixture.registry.summary(fixture.second)?.state == "finishedTurn" })
        #expect(await fixture.runs() == [false, true])
        // OpenRun asked for the end, so the first thread shows no failure.
        #expect(await fixture.registry.summary(fixture.first)?.state == "finishedTurn")
        await fixture.end()
    }
}
