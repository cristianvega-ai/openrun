import TerminalTheme

/// The fonts and colors of a chat: a plain value that the window's theme
/// gives, so the chat and the rest of the window look like one (decision
/// of 2026-10-12).
public struct ChatAppearance: Equatable, Hashable, Sendable {
    public var light: ChatColors
    public var dark: ChatColors
    /// The size of prose in points. Other text sizes follow from it.
    public var bodyFontSize: Double
    /// The font of code, commands, output and diffs. Nil means the
    /// system's monospaced font, which is the terminal's default.
    public var codeFontName: String?
    public var codeFontSize: Double

    public init(light: ChatColors, dark: ChatColors, bodyFontSize: Double = 14, codeFontName: String? = nil, codeFontSize: Double = 12) {
        self.light = light
        self.dark = dark
        self.bodyFontSize = bodyFontSize
        self.codeFontName = codeFontName
        self.codeFontSize = codeFontSize
    }

    /// The Graphite theme of the decision of 2026-10-26.
    public static let graphite = ChatAppearance(
        light: ChatColors(theme: .graphite(for: .light)), dark: ChatColors(theme: .graphite(for: .dark)))
}
