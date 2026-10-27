/// The blink of the cursor. A program asks for a blinking cursor with DECSCUSR.
/// The cursor blinks only while the window is the key window, and it shows
/// steadily for a short time after each key, so the user does not lose it while typing.
@MainActor
final class CursorBlink {
    /// The cursor is shown for 500 ms and hidden for 500 ms: the period is 1 second. It stays shown for 1 second after a key.
    static let phaseDuration: Duration = .milliseconds(500)
    static let steadyDuration: Duration = .seconds(1)

    private let clock: any InputClock
    private let onChange: @MainActor (Bool) -> Void
    private var timer: (any InputTimer)?
    private(set) var isShown = true

    init(clock: any InputClock, onChange: @escaping @MainActor (Bool) -> Void) {
        (self.clock, self.onChange) = (clock, onChange)
    }

    func update(programBlinks: Bool, windowIsKey: Bool) {
        let blinks = programBlinks && windowIsKey
        guard blinks != (timer != nil) else { return }
        if blinks {
            start(after: Self.phaseDuration)
        } else {
            timer?.cancel()
            timer = nil
            show()
        }
    }

    /// Shows the cursor and starts the steady time again.
    func keyPressed() {
        guard timer != nil else { return }
        show()
        start(after: Self.steadyDuration)
    }

    private func start(after delay: Duration) {
        timer?.cancel()
        timer = clock.schedule(after: delay, repeating: Self.phaseDuration) { [weak self] in
            guard let self else { return }
            isShown.toggle()
            onChange(isShown)
        }
    }

    private func show() {
        guard !isShown else { return }
        isShown = true
        onChange(true)
    }
}
