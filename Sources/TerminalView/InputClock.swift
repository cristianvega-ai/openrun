import Foundation

/// The time and the timers of the input. Cursor blink, the limit of a
/// synchronized update, the flash of the bell and the fade of the scroll bar
/// use it, so a test can use a clock that it moves itself.
@MainActor
protocol InputClock: AnyObject {
    var now: ContinuousClock.Instant { get }

    /// Runs `action` on the main thread after `delay`, and again for each `interval` if there is one.
    func schedule(after delay: Duration, repeating interval: Duration?, _ action: @escaping @MainActor () -> Void) -> any InputTimer
}

extension InputClock {
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> any InputTimer {
        schedule(after: delay, repeating: nil, action)
    }
}

@MainActor
protocol InputTimer: AnyObject {
    func cancel()
}

/// The clock of the system. Its timers run in the common modes of the run loop, so they
/// also run while the user drags or scrolls.
@MainActor
final class SystemInputClock: InputClock {
    private final class SystemTimer: InputTimer {
        let timer: Timer
        init(_ timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }

    var now: ContinuousClock.Instant { .now }

    func schedule(after delay: Duration, repeating interval: Duration?, _ action: @escaping @MainActor () -> Void) -> any InputTimer {
        func seconds(_ duration: Duration) -> TimeInterval {
            TimeInterval(duration.components.seconds) + TimeInterval(duration.components.attoseconds) / 1e18
        }
        let timer = Timer(fire: Date(timeIntervalSinceNow: seconds(delay)), interval: interval.map(seconds) ?? 0, repeats: interval != nil) { _ in
            MainActor.assumeIsolated(action)
        }
        RunLoop.main.add(timer, forMode: .common)
        return SystemTimer(timer)
    }
}
