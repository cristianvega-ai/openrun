import GhosttyVt

extension Terminal {
    /// Selects the word under a cell, as a double click does.
    public func selectWord(at cell: ViewportCell) throws {
        var options = GhosttyTerminalSelectWordOptions()
        options.size = MemoryLayout<GhosttyTerminalSelectWordOptions>.size
        options.ref = try gridReference(at: cell)
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        try TerminalEmulationError.check(ghostty_terminal_select_word(handle, &options, &selection), from: "ghostty_terminal_select_word")
        try select(&selection)
    }

    /// Selects the line under a cell, as a triple click does.
    public func selectLine(at cell: ViewportCell) throws {
        var options = GhosttyTerminalSelectLineOptions()
        options.size = MemoryLayout<GhosttyTerminalSelectLineOptions>.size
        options.ref = try gridReference(at: cell)
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        try TerminalEmulationError.check(ghostty_terminal_select_line(handle, &options, &selection), from: "ghostty_terminal_select_line")
        try select(&selection)
    }

    /// The hyperlink (OSC 8) of a cell, or `nil`.
    public func hyperlink(at cell: ViewportCell) -> String? {
        guard var reference = try? gridReference(at: cell) else { return nil }
        var length = 0
        // The first call only measures the address.
        guard ghostty_grid_ref_hyperlink_uri(&reference, nil, 0, &length) == GHOSTTY_OUT_OF_SPACE, length > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: length)
        guard ghostty_grid_ref_hyperlink_uri(&reference, &bytes, length, &length) == GHOSTTY_SUCCESS else { return nil }
        return String(decoding: bytes.prefix(length), as: UTF8.self)
    }

    public func clearSelection() {
        _ = ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_SELECTION, nil)
    }

    public var hasSelection: Bool {
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        return ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_SELECTION, &selection) == GHOSTTY_SUCCESS
    }

    /// The selected text for the clipboard: soft wraps joined, trailing
    /// spaces trimmed. `nil` when nothing is selected.
    public func selectedText() -> String? {
        var options = GhosttyTerminalSelectionFormatOptions()
        options.size = MemoryLayout<GhosttyTerminalSelectionFormatOptions>.size
        options.emit = GHOSTTY_FORMATTER_FORMAT_PLAIN
        options.unwrap = true
        options.trim = true
        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        guard ghostty_terminal_selection_format_alloc(handle, nil, options, &output, &length) == GHOSTTY_SUCCESS,
              let output else { return nil }
        defer { ghostty_free(nil, output, length) }
        return String(decoding: UnsafeBufferPointer(start: output, count: length), as: UTF8.self)
    }

    func gridReference(at cell: ViewportCell) throws -> GhosttyGridRef {
        var point = GhosttyPoint()
        point.tag = GHOSTTY_POINT_TAG_VIEWPORT
        point.value.coordinate = GhosttyPointCoordinate(x: cell.column, y: cell.row)
        var reference = GhosttyGridRef()
        reference.size = MemoryLayout<GhosttyGridRef>.size
        try TerminalEmulationError.check(ghostty_terminal_grid_ref(handle, point, &reference), from: "ghostty_terminal_grid_ref")
        return reference
    }

    /// libghostty-vt tracks the selection: it moves with its text while
    /// output arrives.
    private func select(_ selection: inout GhosttySelection) throws {
        try TerminalEmulationError.check(ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_SELECTION, &selection), from: "ghostty_terminal_set")
    }
}
