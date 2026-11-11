import AgentConversation
import AgentThreads
import Foundation
import SessionProcessHarness
import Testing
@testable import SessionProcess

/// The end of the process of a thread: a stop, the quiet time, and a failure.
@Suite struct ThreadRunnerEndTests {
    /// The first start plays a turn. Each later start is the one of `later`.
    private func settings(later: AgentLaunchSettings) -> @Sendable () async throws -> AgentLaunchSettings {
        let starts = StartCount()
        return { await starts.next() == 1 ? FakeAgentSettings.make() : later }
    }

    private actor StartCount {
        var count = 0
        func next() -> Int {
            count += 1
            return count
        }
    }

    private func processEnds(_ runner: ThreadRunner) async -> [ProcessEnd] {
        await runner.keptEvents.compactMap { if case .processEnded(let end) = $0.kind { end } else { nil } }
    }

    @Test func aStopEndsTheTurnAndTheProcessAndTheNextMessageResumes() async throws {
        let runner = ThreadRunner(record: FakeAgentSettings.record(), launchSettings: settings(later: FakeAgentSettings.make(mode: "neverEnds")))
        try await runner.send(text: "First.")
        #expect(await eventually { await runner.state == .finishedTurn })
        await runner.endProcess()
        #expect(await !runner.isProcessRunning)
        #expect(await processEnds(runner) == [ProcessEnd(exitStatus: 0, wasRequested: true)])

        // The second process resumes, and its turn never ends by itself.
        try await runner.send(text: "Second.")
        try await runner.send(text: "Third, which waits.")
        #expect(await eventually { await runner.state == .inProgress })
        await runner.stop()
        let (isRunning, isBusy, state) = await (runner.isProcessRunning, runner.isBusy, runner.state)
        #expect(!isRunning && !isBusy && state != .inProgress)
        #expect(await processEnds(runner).last?.wasRequested == true)
        let notices = await runner.keptEvents.compactMap { if case .notice(let notice) = $0.kind { notice.text } else { nil } }
        #expect(notices == ["The stop removed 1 messages that waited for the agent."])
        // A stop when nothing runs changes nothing.
        let count = await runner.keptEvents.count
        await runner.stop()
        #expect(await runner.keptEvents.count == count)
        await runner.close()
    }

    @Test func aProcessWithNoWorkEndsAfterTheQuietTimeAndATurnKeepsItsProcess() async throws {
        let quietTime = Duration.milliseconds(300)
        let runner = ThreadRunner(record: FakeAgentSettings.record(), quietTime: quietTime, launchSettings: settings(later: FakeAgentSettings.make(mode: "neverEnds")))
        try await runner.send(text: "First.")
        #expect(await eventually { await runner.state == .finishedTurn })
        #expect(await eventually { await !runner.isProcessRunning })
        // OpenRun asked for the end, so the thread shows no failure.
        #expect(await processEnds(runner) == [ProcessEnd(exitStatus: 0, wasRequested: true)])
        #expect(await runner.state == .finishedTurn)

        // The next message starts a process, and it stays while its turn runs.
        try await runner.send(text: "Second.")
        #expect(await eventually { await runner.state == .inProgress })
        try await Task.sleep(for: quietTime * 3)
        #expect(await runner.isProcessRunning)
        await runner.close()
    }

    @Test func aResumeOfAConversationThatTheAgentDoesNotKnowFailsTheTurn() async throws {
        let runner = ThreadRunner(record: FakeAgentSettings.record(), launchSettings: settings(later: FakeAgentSettings.make(mode: "unknownConversation")))
        try await runner.send(text: "First.")
        #expect(await eventually { await runner.state == .finishedTurn })
        await runner.endProcess()
        try await runner.send(text: "Second.")
        #expect(await eventually {
            let (state, isRunning) = await (runner.state, runner.isProcessRunning)
            return state == .failed && !isRunning
        })
        let end = try #require(await processEnds(runner).last)
        #expect(end.exitStatus == 1 && !end.wasRequested && end.standardErrorText?.hasPrefix("No conversation found with session ID:") == true)
        await runner.close()
    }
}
