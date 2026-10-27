/// The state of a synchronized update (mode 2026). A program holds the screen
/// while it draws a frame in several steps, so the user never sees half of it.
/// A program that crashes could hold the screen for ever, so the hold ends after
/// 1 second.
@MainActor
final class SynchronizedOutputHold {
    static let limit: Duration = .seconds(1)

    private let clock: any InputClock
    private let onLimit: @MainActor () -> Void
    private var timer: (any InputTimer)?
    private(set) var isHeld = false

    /// - Parameter onLimit: Called when the hold lasted too long. The caller ends the mode of the program.
    init(clock: any InputClock, onLimit: @escaping @MainActor () -> Void) {
        (self.clock, self.onLimit) = (clock, onLimit)
    }

    func begin() {
        isHeld = true
        timer?.cancel()
        timer = clock.schedule(after: Self.limit) { [weak self] in
            self?.isHeld = false
            self?.onLimit()
        }
    }

    func end() {
        isHeld = false
        timer?.cancel()
        timer = nil
    }
}
