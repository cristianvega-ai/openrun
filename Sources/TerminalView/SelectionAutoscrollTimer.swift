import TerminalEmulation

/// Calls a step every 15 ms while a drag of the selection asks the viewport to
/// scroll. libghostty-vt scrolls one row for each step, so the interval sets the speed.
@MainActor
final class SelectionAutoscrollTimer {
    static let interval: Duration = .milliseconds(15)

    private let clock: any InputClock, step: @MainActor () -> Void
    private var timer: (any InputTimer)?

    init(clock: any InputClock, step: @escaping @MainActor () -> Void) {
        self.clock = clock
        self.step = step
    }

    /// Runs the timer while the drag asks for a scroll.
    func update(for direction: SelectionAutoscroll) {
        if direction == .none {
            timer?.cancel()
            timer = nil
        } else if timer == nil {
            timer = clock.schedule(after: Self.interval, repeating: Self.interval) { [weak self] in self?.step() }
        }
    }
}
