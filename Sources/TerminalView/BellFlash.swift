/// The visual bell. A program rings the bell with the control character BEL, and the
/// view makes no sound. It flashes for a short time instead. A second bell during
/// a flash makes the flash longer, not a second flash.
@MainActor
final class BellFlash {
    /// The flash lasts 150 ms: long enough to see and short enough not to annoy.
    static let duration: Duration = .milliseconds(150)

    private let clock: any InputClock
    private let onChange: @MainActor (Bool) -> Void
    private var timer: (any InputTimer)?
    private(set) var isFlashing = false

    init(clock: any InputClock, onChange: @escaping @MainActor (Bool) -> Void) {
        (self.clock, self.onChange) = (clock, onChange)
    }

    func ring() {
        timer?.cancel()
        isFlashing = true
        onChange(true)
        timer = clock.schedule(after: Self.duration) { [weak self] in
            self?.isFlashing = false
            self?.onChange(false)
        }
    }
}
