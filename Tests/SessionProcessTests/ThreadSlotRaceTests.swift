import Foundation
import SessionProcessHarness
import Testing
@testable import SessionProcess

@Suite struct ThreadSlotRaceTests {
    @Test func aGrantDuringADeniedRequestStartsTheWaitingMessage() async throws {
        let gate = SlotGate()
        let runner = ThreadRunner(record: FakeAgentSettings.record(), launchSettings: { FakeAgentSettings.make(mode: "neverEnds") }, takeProcessSlot: { _ in await gate.take() })
        try await runner.send(text: "Work")
        #expect(await eventually { await gate.entered })
        await runner.sendNextMessage()
        await gate.release()
        #expect(await eventually { await runner.isProcessRunning })
        await runner.close()
    }
}

private actor SlotGate {
    var entered = false
    var continuation: CheckedContinuation<Void, Never>?
    var calls = 0
    func take() async -> ProcessSlotAnswer {
        calls += 1
        guard calls == 1 else { return .granted }
        entered = true
        await withCheckedContinuation { continuation = $0 }
        return .waits(limit: 1)
    }
    func release() { continuation?.resume(); continuation = nil }
}
