import GhosttyVt

/// Finds text in a terminal: the screen and the scrollback, as Command-F
/// does. libghostty-vt searches, and the match that the user is at becomes
/// the selection of the terminal, so it shows as a selection does and
/// Copy takes it.
///
/// The search borrows its terminal. Each call must come from the context
/// that uses the terminal, because the search reads it.
public final class TerminalSearch {
    /// The matches of the text that the search looks for now.
    public struct Matches: Equatable, Sendable {
        public var count: Int
        /// The place of the selected match, where 1 is the newest one, or
        /// nil when the text has no match.
        public var selected: Int?

        public init(count: Int = 0, selected: Int? = nil) {
            (self.count, self.selected) = (count, selected)
        }
    }

    private let terminal: Terminal
    private var handle: GhosttySearch?

    public init(terminal: Terminal) throws {
        self.terminal = terminal
        try TerminalEmulationError.check(ghostty_search_new(nil, &handle, terminal.handle), from: "ghostty_search_new")
    }

    deinit {
        ghostty_search_free(handle)
    }

    /// Looks for the text and selects its newest match. The letters of
    /// ASCII match in each case. Empty text ends the search and the
    /// selection.
    public func find(_ text: String) throws -> Matches {
        let bytes = Array(text.utf8)
        try bytes.withUnsafeBufferPointer { buffer in
            var needle = GhosttyString(ptr: buffer.baseAddress, len: buffer.count)
            try TerminalEmulationError.check(ghostty_search_set(handle, GHOSTTY_SEARCH_OPT_NEEDLE, &needle), from: "ghostty_search_set")
        }
        guard !bytes.isEmpty else {
            terminal.clearSelection()
            return Matches()
        }
        return try move(GHOSTTY_SEARCH_OPT_SELECT_NEXT)
    }

    /// Selects the match before the selected one in time: from the
    /// bottom of the screen up into the scrollback. After the oldest
    /// match comes the newest one.
    public func selectOlder() throws -> Matches {
        try move(GHOSTTY_SEARCH_OPT_SELECT_NEXT)
    }

    /// Selects the match after the selected one in time.
    public func selectNewer() throws -> Matches {
        try move(GHOSTTY_SEARCH_OPT_SELECT_PREV)
    }

    /// The step catches up with the terminal first, and it scrolls the
    /// selected match into the viewport.
    private func move(_ option: GhosttySearchOption) throws -> Matches {
        let result = ghostty_search_set(handle, option, nil)
        // No value means that the text has no match.
        if result != GHOSTTY_NO_VALUE { try TerminalEmulationError.check(result, from: "ghostty_search_set") }
        var (count, index) = (0, 0)
        try TerminalEmulationError.check(ghostty_search_get(handle, GHOSTTY_SEARCH_DATA_TOTAL_MATCHES, &count), from: "ghostty_search_get")
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        guard ghostty_search_get(handle, GHOSTTY_SEARCH_DATA_SELECTED_INDEX, &index) == GHOSTTY_SUCCESS,
              ghostty_search_get(handle, GHOSTTY_SEARCH_DATA_SELECTED_MATCH, &selection) == GHOSTTY_SUCCESS else {
            terminal.clearSelection()
            return Matches(count: count)
        }
        try TerminalEmulationError.check(ghostty_terminal_set(terminal.handle, GHOSTTY_TERMINAL_OPT_SELECTION, &selection), from: "ghostty_terminal_set")
        return Matches(count: count, selected: index + 1)
    }
}
