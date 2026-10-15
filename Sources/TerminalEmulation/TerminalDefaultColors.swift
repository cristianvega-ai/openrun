import GhosttyVt

/// The default colors of a terminal.
///
/// A default is the color that the embedder chose. A program can replace it
/// with `OSC 4`, `OSC 10`, `OSC 11` and `OSC 12`, and libghostty-vt keeps that
/// program color apart from the default. A change of a default never removes
/// a color that a program set, and a reset by the program brings back the
/// default.
///
/// A snapshot carries the colors that are in force, so a restored terminal
/// keeps the defaults of the session process. A client that restores a
/// snapshot calls these to give the terminal its own colors.
///
/// While a reply handler is installed, `write` sets the foreground and the
/// background from the appearance each time the appearance changes. A color
/// set here then lasts only until the next change of the appearance.
extension Terminal {
    /// The default foreground, or `nil` when none is set.
    public var defaultForegroundColor: TerminalColor? {
        defaultColor(GHOSTTY_TERMINAL_DATA_COLOR_FOREGROUND_DEFAULT)
    }

    /// The default background, or `nil` when none is set.
    public var defaultBackgroundColor: TerminalColor? {
        defaultColor(GHOSTTY_TERMINAL_DATA_COLOR_BACKGROUND_DEFAULT)
    }

    /// The default cursor color, or `nil` when none is set.
    public var defaultCursorColor: TerminalColor? {
        defaultColor(GHOSTTY_TERMINAL_DATA_COLOR_CURSOR_DEFAULT)
    }

    /// Sets the default foreground, or clears it when `color` is `nil`.
    public func setDefaultForegroundColor(_ color: TerminalColor?) throws {
        try setDefaultColor(GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, to: color)
    }

    /// Sets the default background, or clears it when `color` is `nil`.
    public func setDefaultBackgroundColor(_ color: TerminalColor?) throws {
        try setDefaultColor(GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, to: color)
    }

    /// Sets the default cursor color, or clears it when `color` is `nil`.
    public func setDefaultCursorColor(_ color: TerminalColor?) throws {
        try setDefaultColor(GHOSTTY_TERMINAL_OPT_COLOR_CURSOR, to: color)
    }

    /// The default 256-color palette. It is the built-in palette until a call
    /// to `setDefaultPalette` replaces it.
    public var defaultPalette: [TerminalColor] {
        var colors = [GhosttyColorRgb](repeating: GhosttyColorRgb(), count: Terminal.paletteSize)
        guard ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_COLOR_PALETTE_DEFAULT, &colors) == GHOSTTY_SUCCESS else { return [] }
        return colors.map { TerminalColor(red: $0.r, green: $0.g, blue: $0.b) }
    }

    /// Sets the default palette, or restores the built-in one when `colors`
    /// is `nil`. Entries that a program changed with `OSC 4` keep that color.
    ///
    /// - Throws: `TerminalEmulationError` when `colors` does not hold exactly
    ///   256 colors.
    public func setDefaultPalette(_ colors: [TerminalColor]?) throws {
        guard let colors else {
            try TerminalEmulationError.check(
                ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, nil), from: "ghostty_terminal_set")
            return
        }
        guard colors.count == Terminal.paletteSize else {
            throw TerminalEmulationError.invalidValue(in: "Terminal.setDefaultPalette")
        }
        var converted = colors.map { GhosttyColorRgb(r: $0.red, g: $0.green, b: $0.blue) }
        try TerminalEmulationError.check(
            ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_COLOR_PALETTE, &converted), from: "ghostty_terminal_set")
    }

    private static let paletteSize = 256

    private func defaultColor(_ data: GhosttyTerminalData) -> TerminalColor? {
        var color = GhosttyColorRgb()
        // No value means that no default is set.
        guard ghostty_terminal_get(handle, data, &color) == GHOSTTY_SUCCESS else { return nil }
        return TerminalColor(red: color.r, green: color.g, blue: color.b)
    }

    private func setDefaultColor(_ option: GhosttyTerminalOption, to color: TerminalColor?) throws {
        guard let color else {
            try TerminalEmulationError.check(ghostty_terminal_set(handle, option, nil), from: "ghostty_terminal_set")
            return
        }
        var converted = GhosttyColorRgb(r: color.red, g: color.green, b: color.blue)
        try TerminalEmulationError.check(ghostty_terminal_set(handle, option, &converted), from: "ghostty_terminal_set")
    }
}
