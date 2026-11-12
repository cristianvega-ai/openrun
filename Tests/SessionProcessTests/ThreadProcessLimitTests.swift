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

    @Test func aMessageWaitsWhileEveryAgentWorksAndGoesOutWhenOneEnds() async throws {
        let fixture = try await Fixture(mode: "neverEnds")
        try await fixture.firstRunner.send(text: "One.")
        #expect(await eventually { await fixture.registry.summary(fixture.first)?.state == "inProgress" })
        try await fixture.secondRunner.send(text: "Two.")
        try await fixture.secondRunner.send(text: "Three.")
        let waiting = await fixture.registry.summary(fixture.second)
        #expect(waiting?.waitingMessageCount == 2 && waiting?.isProcessRunning == false)
        let notices = await fixture.secondRunner.keptEvents.compactMap { if case .notice(let notice) = $0.kind { notice.text } else { nil } }
        #expect(notices.count == 1 && notices.first?.contains("at most 1 agent at one time") == true)

        await fixture.firstRunner.stop()
        #expect(await eventually { await fixture.runs() == [false, true] })
        #expect(await eventually { await fixture.registry.summary(fixture.second)?.state == "inProgress" })
        #expect(await fixture.registry.summary(fixture.second)?.waitingMessageCount == 1)
        await fixture.end()
    }

    @Test func aHigherLimitOfTheSettingsStartsTheAgentThatWaits() async throws {
        let fixture = try await Fixture(mode: "neverEnds")
        try await fixture.firstRunner.send(text: "One.")
        #expect(await eventually { await fixture.registry.summary(fixture.first)?.state == "inProgress" })
        try await fixture.secondRunner.send(text: "Two.")
        #expect(await fixture.runs() == [true, false])
        await fixture.registry.updateSettings(model: "sonnet", permissionMode: "plan", processLimit: 2, version: 2)
        #expect(await eventually { await fixture.runs() == [true, true] })
        // The settings also give the model and the mode of the next thread. Older settings change nothing.
        await fixture.registry.updateSettings(model: "haiku", permissionMode: "default", processLimit: 1, version: 1)
        let third = try await fixture.registry.create(agent: "claude-code", folder: fixture.folder.path, model: nil, permissionMode: nil, name: nil)
        #expect(third.model == "sonnet" && third.permissionMode == "plan")
        await fixture.end()
    }

    @Test func aThreadThatLostItsMessagesLeavesTheSlotToTheThreadAfterIt() async throws {
        let fixture = try await Fixture(mode: "neverEnds")
        let third = try await fixture.registry.create(agent: "claude-code", folder: fixture.folder.path, model: nil, permissionMode: nil, name: nil).identifier
        try await fixture.firstRunner.send(text: "One.")
        #expect(await eventually { await fixture.registry.summary(fixture.first)?.state == "inProgress" })
        // The second thread waits in line, and a stop removes its message.
        try await fixture.secondRunner.send(text: "Two.")
        try await fixture.registry.runner(for: third).send(text: "Three.")
        await fixture.secondRunner.stop()
        await fixture.firstRunner.stop()
        #expect(await eventually { await fixture.registry.summary(third)?.isProcessRunning == true })
        #expect(await fixture.runs() == [false, false])
        await fixture.end()
    }

    @Test func theCloseOfAThreadGivesItsSlotToTheThreadThatWaits() async throws {
        let fixture = try await Fixture(mode: "neverEnds")
        try await fixture.firstRunner.send(text: "One.")
        #expect(await eventually { await fixture.registry.summary(fixture.first)?.state == "inProgress" })
        try await fixture.secondRunner.send(text: "Two.")
        try await fixture.registry.close(fixture.first)
        #expect(await eventually { await fixture.registry.summary(fixture.second)?.isProcessRunning == true })
        await fixture.end()
    }
}
