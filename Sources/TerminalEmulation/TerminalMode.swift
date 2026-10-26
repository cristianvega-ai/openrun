import GhosttyVt

/// The modes a terminal view reads to decide how input goes to the program.
public enum TerminalMode: Sendable, CaseIterable {
    case applicationCursorKeys
    case bracketedPaste
    case focusReports
    case alternateScroll
    case synchronizedOutput
    case normalMouseReports
    case buttonMouseReports
    case anyMouseReports

    /// The mode constants of libghostty-vt are C macros that call a static
    /// inline function, and Swift cannot import macros. So the number of
    /// each mode goes through `ghostty_mode_new` here.
    var raw: GhosttyMode {
        switch self {
        case .applicationCursorKeys: ghostty_mode_new(1, false)
        case .bracketedPaste: ghostty_mode_new(2004, false)
        case .focusReports: ghostty_mode_new(1004, false)
        case .alternateScroll: ghostty_mode_new(1007, false)
        case .synchronizedOutput: ghostty_mode_new(2026, false)
        case .normalMouseReports: ghostty_mode_new(1000, false)
        case .buttonMouseReports: ghostty_mode_new(1002, false)
        case .anyMouseReports: ghostty_mode_new(1003, false)
        }
    }
}

extension Terminal {
    public func isModeEnabled(_ mode: TerminalMode) -> Bool {
        var configuration = GhosttyTerminalModeConfig()
        configuration.mode = mode.raw
        guard ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_MODE, &configuration) == GHOSTTY_SUCCESS else { return false }
        return configuration.value
    }

    /// Turns a mode on or off, as a view does when a synchronized update
    /// lasts too long.
    public func setMode(_ mode: TerminalMode, enabled: Bool) throws {
        var configuration = GhosttyTerminalModeConfig()
        configuration.mode = mode.raw
        configuration.value = enabled
        try TerminalEmulationError.check(ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_MODE, &configuration), from: "ghostty_terminal_set")
    }
}
