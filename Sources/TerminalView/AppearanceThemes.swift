import TerminalEmulation
import TerminalTheme

/// The themes of a view for the light and the dark appearance of macOS. The
/// view shows the one that fits its appearance, and changes when it changes.
public struct AppearanceThemes: Equatable, Sendable {
    public var light: TerminalTheme
    public var dark: TerminalTheme

    public init(light: TerminalTheme, dark: TerminalTheme) {
        (self.light, self.dark) = (light, dark)
    }

    /// The Graphite theme of the decision of 2026-10-26, the default of a view.
    public static let graphite = AppearanceThemes(light: .graphite(for: .light), dark: .graphite(for: .dark))

    public func theme(for scheme: TerminalColorScheme) -> TerminalTheme {
        scheme == .dark ? dark : light
    }
}
