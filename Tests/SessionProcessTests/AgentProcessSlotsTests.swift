import Foundation
import Testing
@testable import SessionProcess

@Suite struct AgentProcessSlotsTests {
    private let first = UUID(), second = UUID(), third = UUID(), fourth = UUID()

    @Test func aThreadGetsASlotWhileOneIsFreeAndKeepsIt() {
        var slots = AgentProcessSlots(limit: 2)
        let taken = [slots.take(for: first), slots.take(for: second), slots.take(for: first)]
        #expect(taken == [true, true, true])
        #expect(slots.holders == [first, second] && slots.waiting.isEmpty)
        #expect(AgentProcessSlots().limit == 8)
    }

    @Test func aThreadPastTheLimitWaitsInLineOnce() {
        var slots = AgentProcessSlots(limit: 1)
        let taken = [slots.take(for: first), slots.take(for: second), slots.take(for: third), slots.take(for: second)]
        #expect(taken == [true, false, false, false])
        #expect(slots.holders == [first] && slots.waiting == [second, third])
    }

    @Test func aFreeSlotGoesToTheThreadThatWaitedLongest() {
        var slots = AgentProcessSlots(limit: 1)
        _ = (slots.take(for: first), slots.take(for: second), slots.take(for: third))
        let next = slots.release(first)
        #expect(next == second && slots.holders == [second] && slots.waiting == [third])
        // A thread with no slot gives none back.
        let none = [slots.release(fourth), slots.release(third)]
        #expect(none == [nil, nil] && slots.holders == [second])
        let last = [slots.release(second), slots.release(third)]
        #expect(last == [third, nil] && slots.holders.isEmpty)
    }

    @Test func aClosedThreadLeavesTheLineAndGivesItsSlotBack() {
        var slots = AgentProcessSlots(limit: 1)
        _ = (slots.take(for: first), slots.take(for: second), slots.take(for: third))
        let fromLine = slots.remove(second)
        #expect(fromLine == nil && slots.waiting == [third])
        let fromHolder = slots.remove(first)
        #expect(fromHolder == third && slots.holders == [third] && slots.waiting.isEmpty)
    }
}
