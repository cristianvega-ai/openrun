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

}
