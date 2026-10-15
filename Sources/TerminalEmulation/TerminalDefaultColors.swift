import GhosttyVt

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
