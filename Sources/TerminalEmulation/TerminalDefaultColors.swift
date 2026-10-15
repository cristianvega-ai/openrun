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

    private func defaultColor(_ data: GhosttyTerminalData) -> TerminalColor? {
        var color = GhosttyColorRgb()
        // No value means that no default is set.
        guard ghostty_terminal_get(handle, data, &color) == GHOSTTY_SUCCESS else { return nil }
        return TerminalColor(red: color.r, green: color.g, blue: color.b)
    }

}
