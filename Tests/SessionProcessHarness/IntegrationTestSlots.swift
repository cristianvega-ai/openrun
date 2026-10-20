import Testing

/// Lets at most `slotCount` integration tests of one test product run at
/// once. Each one starts real processes, and too many at once make the tests
/// that check time limits fail on a busy Mac.
actor IntegrationTestSlots {
    /// The owner may change this number. A larger one must first pass three
    /// full test runs that start at the same time.
    static let slotCount = 8

    static let shared = IntegrationTestSlots()

    private var slotsInUse = 0
    private var waitingTests: [CheckedContinuation<Void, Never>] = []

    /// Returns when the test may start.
    func enter(for test: Test) async {
        if slotsInUse < Self.slotCount {
            slotsInUse += 1
            return
        }
        await withCheckedContinuation { waitingTests.append($0) }
    }

    /// Gives the slot of a test that ended to the test that waited longest.
    func leave(for test: Test) {
        if waitingTests.isEmpty {
            slotsInUse -= 1
        } else {
            waitingTests.removeFirst().resume()
        }
    }
}
