import Synchronization
import Testing
@testable import PseudoTerminal

/// Records the outcomes that an input backlog reports.
private final class OutcomeLog: Sendable {
    private let entries = Mutex<[String]>([])

    func completion(_ name: String) -> InputBacklog.Completion {
        { outcome in self.entries.withLock { $0.append("\(name):\(outcome)") } }
    }

    var all: [String] { entries.withLock { $0 } }
}

/// Owners for the tests. Each object gives one identity, and lives as long
/// as the tests, so no other object can reuse it.
private final class Owner: Sendable {}
private let firstOwner = Owner()
private let secondOwner = Owner()

private func bytes(_ count: Int, _ value: UInt8) -> [UInt8] {
    [UInt8](repeating: value, count: count)
}

/// Takes everything from the front of the backlog, as a terminal that reads
/// at once would, and returns the bytes in order.
private func drain(_ backlog: inout InputBacklog) -> [UInt8] {
    var taken: [UInt8] = []
    while let front = backlog.front {
        taken += front
        backlog.removeFromFront(front.count)
    }
    return taken
}

@Suite struct InputBacklogUnitTests {
    @Test func typedInputPastTheLimitWaitsAndGoesInInOrder() {
        var backlog = InputBacklog()
        let log = OutcomeLog()
        let owner = ObjectIdentifier(firstOwner)
        let piece = InputBacklog.typedLimit / 2
        _ = backlog.addTyped(bytes(piece, 1), owner: owner, staysWithoutOwner: true, completion: log.completion("first"))
        _ = backlog.addTyped(bytes(piece, 2), owner: owner, staysWithoutOwner: true, completion: log.completion("second"))
        _ = backlog.addTyped(bytes(1, 3), owner: owner, staysWithoutOwner: true, completion: log.completion("third"))
        backlog.admitWaiting().forEach { $0.deliver() }
        #expect(log.all == ["first:taken", "second:taken"])
        #expect(backlog.pendingByteCount == InputBacklog.typedLimit)
        #expect(backlog.hasWaitingInput)

        // One byte out makes room for the byte that waits.
        backlog.removeFromFront(1)
        backlog.admitWaiting().forEach { $0.deliver() }
        #expect(log.all == ["first:taken", "second:taken", "third:taken"])
        #expect(!backlog.hasWaitingInput)
    }

    @Test func aPieceLargerThanTheLimitWaitsForAnEmptyBacklog() {
        var backlog = InputBacklog()
        let log = OutcomeLog()
        let owner = ObjectIdentifier(firstOwner)
        _ = backlog.addTyped(bytes(10, 1), owner: owner, staysWithoutOwner: true, completion: log.completion("small"))
        _ = backlog.addTyped(bytes(InputBacklog.typedLimit + 1, 2), owner: owner, staysWithoutOwner: true, completion: log.completion("large"))
        backlog.admitWaiting().forEach { $0.deliver() }
        #expect(log.all == ["small:taken"])
        _ = drain(&backlog)
        backlog.admitWaiting().forEach { $0.deliver() }
        #expect(log.all == ["small:taken", "large:taken"])
    }

    @Test func answersGoInAtOnceAndCountApart() {
        var backlog = InputBacklog()
        let owner = ObjectIdentifier(firstOwner)
        _ = backlog.addTyped(bytes(InputBacklog.typedLimit, 1), owner: owner, staysWithoutOwner: true) { _ in }
        _ = backlog.admitWaiting()
        backlog.addAnswer(bytes(InputBacklog.answerLimit + 1, 2))
        #expect(backlog.pendingByteCount == InputBacklog.typedLimit + InputBacklog.answerLimit + 1)
        #expect(!backlog.answersAreWithinLimit)
        _ = drain(&backlog)
        #expect(backlog.answersAreWithinLimit)
        #expect(backlog.pendingByteCount == 0)
    }

    /// An answer went into the backlog at once, so it passed
    /// typed input that waited for room, and the program read it first.
    @Test func anAnswerGoesBehindTypedInputThatWaits() {
        var backlog = InputBacklog()
        let log = OutcomeLog()
        let owner = ObjectIdentifier(firstOwner)
        _ = backlog.addTyped(bytes(InputBacklog.typedLimit, 1), owner: owner, staysWithoutOwner: true, completion: log.completion("full"))
        _ = backlog.addTyped(bytes(4, 2), owner: owner, staysWithoutOwner: true, completion: log.completion("waiting"))
        backlog.admitWaiting().forEach { $0.deliver() }
        #expect(log.all == ["full:taken"])
        backlog.addAnswer(bytes(3, 9))
        // The answer counts toward its own limit while it waits.
        #expect(backlog.pendingAnswerByteCount == 3)

        // The program reads everything, as a terminal that reads at once would.
        var taken: [UInt8] = []
        while let front = backlog.front {
            taken += front
            backlog.removeFromFront(front.count)
            backlog.admitWaiting().forEach { $0.deliver() }
        }
        #expect(taken.count == InputBacklog.typedLimit + 7)
        #expect(Array(taken.suffix(7)) == [2, 2, 2, 2, 9, 9, 9])
        #expect(log.all == ["full:taken", "waiting:taken"])
        #expect(backlog.pendingAnswerByteCount == 0)
    }

    @Test func closingFailsTheWaitingInputAndRefusesMore() {
        var backlog = InputBacklog()
        let log = OutcomeLog()
        let owner = ObjectIdentifier(firstOwner)
        _ = backlog.addTyped(bytes(InputBacklog.typedLimit, 1), owner: owner, staysWithoutOwner: true, completion: log.completion("in"))
        _ = backlog.addTyped(bytes(1, 2), owner: owner, staysWithoutOwner: true, completion: log.completion("waiting"))
        backlog.admitWaiting().forEach { $0.deliver() }
        backlog.close().forEach { $0.deliver() }
        backlog.addTyped(bytes(1, 3), owner: owner, staysWithoutOwner: true, completion: log.completion("late")).forEach { $0.deliver() }
        #expect(log.all == ["in:taken", "waiting:programEnded", "late:programEnded"])
        #expect(backlog.isClosed)
        #expect(backlog.front == nil)
        #expect(backlog.pendingByteCount == 0)
    }
}
