import AgentConversation
import AgentProgram
import Darwin
import Testing

/// The special cases of the fake agent, through the program and the decoder.
@Suite struct FakeAgentFailureTests {
    @Test func sigintStopsATurnThatNeverEnds() async throws {
        var run = try FakeAgentRun(turns: ["stopped-turn"], mode: "neverEnds")
        _ = try await run.send("Run a long command.")
        #expect(await run.read { if case .toolCallStarted = $0 { true } else { false } } != nil)
        run.program.send(signal: SIGINT)
        #expect(await run.readTurn()?.outcome == .stopped)
        #expect(await run.program.waitForExit() == .exited(status: 0))
        #expect(run.transcript.state == .idle)
    }

    @Test func outputCutInALineEndsWithACutLine() async throws {
        var run = try FakeAgentRun(turns: ["plain-turn"], mode: "cutLine")
        _ = try await run.send("Reply with the single word ok.")
        #expect(await run.readTurn() == nil)
        guard case .unknown(let line)? = run.events.last?.kind else {
            Issue.record("The last event is not a cut line")
            return
        }
        #expect(line.reason == .cutShort)
        #expect(await run.program.waitForExit() == .exited(status: 1))
    }

    @Test func aCrashEndsTheOutputWithoutTheEndOfTheTurn() async throws {
        var run = try FakeAgentRun(turns: ["command-turn"], mode: "crash")
        _ = try await run.send("Run a command.")
        #expect(await run.readTurn() == nil)
        #expect(await run.program.waitForExit() == .signaled(signal: SIGKILL))
        #expect(run.transcript.state == .inProgress)
    }

    @Test func aFloodComesWholeAndTheTurnStillEnds() async throws {
        let floodBytes = 12 * 1024 * 1024
        var run = try FakeAgentRun(turns: ["plain-turn"], mode: "flood", environment: ["FAKE_AGENT_FLOOD_BYTES": "\(floodBytes)"])
        _ = try await run.send("Reply with the single word ok.")
        #expect(await run.readTurn()?.outcome == .done)
        let deltaBytes = run.events.reduce(0) { total, event in
            if case .agentTextDelta(let delta) = event.kind { total + delta.text.utf8.count } else { total }
        }
        #expect(deltaBytes == floodBytes + "ok".utf8.count)
        run.program.closeInput()
        #expect(await run.program.waitForExit() == .exited(status: 0))
    }
}
