import AgentConversation
import AgentThreads
import Foundation
import SessionProcessHarness
import Testing
@testable import SessionProcess

/// An agent that fails, and a client that attaches in the middle of a turn.
@Suite struct ThreadRunnerFailureTests {
    private func turnEnds(_ runner: ThreadRunner) async -> [TurnEnd] {
        await runner.keptEvents.compactMap { if case .turnEnded(let end) = $0.kind { end } else { nil } }
    }

    @Test func anAgentThatCrashesEndsItsTurnAndTheThreadGoesOn() async throws {
        let runner = ThreadRunner(record: FakeAgentSettings.record()) { FakeAgentSettings.make(mode: "crash") }
        try await runner.send(text: "Reply with the single word ok.")
        #expect(await eventually {
            let (isRunning, isBusy) = await (runner.isProcessRunning, runner.isBusy)
            return !isRunning && !isBusy
        })
        let ends = await runner.keptEvents.compactMap { if case .processEnded(let end) = $0.kind { end } else { nil } }
        #expect(ends == [ProcessEnd(exitStatus: nil, signal: SIGKILL, wasRequested: false)])
        #expect(await runner.state == .failed)
        await runner.close()
    }

    @Test func aProgramThatDoesNotExistFailsTheTurnWithTheReason() async throws {
        var settings = FakeAgentSettings.make()
        settings.program = "/no/such/agent"
        let runner = ThreadRunner(record: FakeAgentSettings.record()) { [settings] in settings }
        try await runner.send(text: "First.")
        #expect(await eventually { await !turnEnds(runner).isEmpty })
        let end = try #require(await turnEnds(runner).first)
        #expect(end.outcome == .failed && end.errorText?.hasPrefix("The agent could not take the message.") == true)
        let (isRunning, isBusy) = await (runner.isProcessRunning, runner.isBusy)
        #expect(!isRunning && !isBusy)
    }

    @Test func aFolderThatIsGoneFailsTheTurn() async throws {
        let runner = ThreadRunner(record: FakeAgentSettings.record(folder: "/no/such/folder")) { FakeAgentSettings.make() }
        try await runner.send(text: "First.")
        #expect(await eventually { await turnEnds(runner).first?.outcome == .failed })
    }

    /// The events before the attach and after it are the events of the thread, each one once.
    @Test func aClientThatAttachesInATurnGetsEachEventOnce() async throws {
        // Stop releases the result, so the late client attaches during the turn.
        let settings = FakeAgentSettings.make(turns: ["edit-turn"], mode: "neverEnds")
        let runner = ThreadRunner(record: FakeAgentSettings.record()) { settings }
        let early = ThreadDeliveries(), late = ThreadDeliveries()
        await runner.attach(ObjectIdentifier(early), listener: early.listener)
        try await runner.send(text: "Change the file.")
        #expect(await eventually { await runner.keptEvents.count >= 6 })
        await runner.attach(ObjectIdentifier(late), listener: late.listener)
        await runner.stop()
        #expect(await eventually { await !turnEnds(runner).isEmpty })
        // A line of the agent can come after the end of the turn, so the
        // test reads the three until they agree.
        #expect(await eventually {
            let kept = await runner.keptEvents
            return early.events == kept && late.events == kept
        })
        let kept = await runner.keptEvents
        #expect(early.replayCount == 0 && (late.replayCount ?? 0) >= 6 && (late.replayCount ?? 0) < kept.count)
        await runner.detach(ObjectIdentifier(early))
        await runner.close()
        #expect(late.isClosed && !early.isClosed)
        // A client that attaches to a closed thread hears only of the close.
        let after = ThreadDeliveries()
        await runner.attach(ObjectIdentifier(after), listener: after.listener)
        #expect(after.isClosed && after.events.isEmpty)
    }
}
