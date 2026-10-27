import TerminalEmulation

/// The colors of a terminal that a user sees. The Graphite theme of the
/// decision of 2026-10-26 has a light and a dark version.
public struct TerminalTheme: Equatable, Sendable {
    public var background: TerminalColor
    public var foreground: TerminalColor
    public var cursor: TerminalColor
    public var selection: TerminalColor
    /// Colors 0 to 15 of the palette. Colors 16 to 255 stay standard.
    public var firstSixteenColors: [TerminalColor]

    init(background: UInt32, foreground: UInt32, cursor: UInt32, selection: UInt32, firstSixteenColors: [UInt32]) {
        self.background = TerminalColor(hexadecimal: background)
        self.foreground = TerminalColor(hexadecimal: foreground)
        self.cursor = TerminalColor(hexadecimal: cursor)
        self.selection = TerminalColor(hexadecimal: selection)
        self.firstSixteenColors = firstSixteenColors.map(TerminalColor.init(hexadecimal:))
    }

    /// The version of the Graphite theme that fits a macOS appearance.
    public static func graphite(for scheme: TerminalColorScheme) -> TerminalTheme {
        scheme == .dark ? GraphitePalette.dark : GraphitePalette.light
    }

    /// Gives a terminal these colors as its defaults. A program can still
    /// set its own colors with `OSC 4`, `OSC 10`, `OSC 11` and `OSC 12`.
    public func apply(to terminal: Terminal) throws {
        try terminal.setDefaultBackgroundColor(background)
        try terminal.setDefaultForegroundColor(foreground)
        try terminal.setDefaultCursorColor(cursor)
        var palette = terminal.defaultPalette
        palette.replaceSubrange(0..<min(16, palette.count), with: firstSixteenColors)
        // The terminal refuses a palette that does not hold 256 colors.
        try terminal.setDefaultPalette(palette)
    }
}
