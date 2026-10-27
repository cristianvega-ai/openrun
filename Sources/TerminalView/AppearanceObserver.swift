import AppKit
import TerminalEmulation

/// Follows the macOS appearance of a view and tells when the light or dark
/// scheme changes. AppKit also reports other changes, such as the accent
/// color, and they must not make a new frame.
struct AppearanceObserver {
    private(set) var scheme: TerminalColorScheme

    init(appearance: NSAppearance) {
        scheme = Self.scheme(of: appearance)
    }

    /// - Returns: `true` when `appearance` has another scheme than the one before.
    mutating func observe(_ appearance: NSAppearance) -> Bool {
        let new = Self.scheme(of: appearance)
        defer { scheme = new }
        return new != scheme
    }

    static func scheme(of appearance: NSAppearance) -> TerminalColorScheme {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}
