import Darwin
import Testing

extension Tag {
    /// A long test that mostly waits and uses little processor time. It
    /// starts at once without a slot, so the longest test of a run does not
    /// also wait in the queue.
    @Tag public static var startsAtOnce: Self
    /// A test that checks wall time, or that changes a setting of the whole
    /// test process, such as the umask. It takes every slot, so no other
    /// integration test of its product runs beside it.
    @Tag public static var takesEverySlot: Self
    /// A test that pushes megabytes of input through a pseudo terminal. It
    /// also takes the lock of `TerminalFloodLock`, so one such test runs at a
    /// time on the whole Mac, whatever the number of test processes. Floods
    /// that run at once slow each other down in the kernel: three at once
    /// take 4.2 s each for 4 MiB, against 0.19 s alone.
    @Tag public static var floodsTerminalInput: Self
}

/// Lets at most `slotCount` integration tests of one test product run at
/// once. Each one starts real processes, and too many at once make the tests
/// that check time limits fail on a busy Mac.
actor IntegrationTestSlots {
    /// The owner may change this number. A larger one must first pass three
    /// full test runs that start at the same time.
    static let slotCount = 8

    /// At most this many tests with the tag `floodsTerminalInput` of one test
    /// process hold a slot at once. The lock of `TerminalFloodLock` lets one
    /// flood run at a time on the whole Mac, so a second one in this process
    /// would only hold a slot while it waits for the lock.
    static let floodingTestCount = 1

    static let shared = IntegrationTestSlots()

    private enum Need {
        case noSlot, oneSlot, floodingSlot, everySlot

        init(_ test: Test) {
            let tags = test.tags
            self = tags.contains(.takesEverySlot) ? .everySlot : tags.contains(.startsAtOnce) ? .noSlot
                : tags.contains(.floodsTerminalInput) ? .floodingSlot : .oneSlot
        }
    }

    private var slotsInUse = 0
    private var testsWithoutSlot = 0
    private var floodingTests = 0
    private var aTestHasEverySlot = false
    private var waitingTests: [(need: Need, continuation: CheckedContinuation<Void, Never>)] = []

    /// Several tests at once can hold more sockets than the usual soft limit
    /// of 256 descriptors. The hard limit stays as it is.
    private init() {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0, limit.rlim_cur < min(limit.rlim_max, 4096) else { return }
        limit.rlim_cur = min(limit.rlim_max, 4096)
        setrlimit(RLIMIT_NOFILE, &limit)
    }

    /// Returns when the test may start.
    func enter(for test: Test) async {
        let need = Need(test)
        if canStart(need) {
            change(need, by: 1)
            return
        }
        await withCheckedContinuation { waitingTests.append((need, $0)) }
    }

    /// Starts each waiting test that can start now, oldest first. A test that
    /// needs every slot does not hold back the tests behind it, so it starts
    /// when the tests before it have ended.
    func leave(for test: Test) {
        change(Need(test), by: -1)
        let waitingBefore = waitingTests
        waitingTests = []
        for waiting in waitingBefore {
            if canStart(waiting.need) {
                change(waiting.need, by: 1)
                waiting.continuation.resume()
            } else {
                waitingTests.append(waiting)
            }
        }
    }

    private func canStart(_ need: Need) -> Bool {
        switch need {
        case .noSlot: !aTestHasEverySlot
        case .oneSlot: slotsInUse < Self.slotCount
        case .floodingSlot: slotsInUse < Self.slotCount && floodingTests < Self.floodingTestCount
        case .everySlot: slotsInUse == 0 && testsWithoutSlot == 0
        }
    }

    private func change(_ need: Need, by step: Int) {
        switch need {
        case .noSlot: testsWithoutSlot += step
        case .oneSlot: slotsInUse += step
        case .floodingSlot:
            slotsInUse += step
            floodingTests += step
        case .everySlot:
            slotsInUse += step * Self.slotCount
            aTestHasEverySlot = step > 0
        }
    }
}
