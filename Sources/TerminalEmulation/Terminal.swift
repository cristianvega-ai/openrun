import Foundation
import GhosttyVt

/// One virtual terminal: it parses the bytes a program writes and keeps the
/// screen, the scrollback, and the cursor.
///
/// A `Terminal` is not thread-safe. Call it from one thread at a time.
/// It owns one libghostty-vt terminal and frees it when it is released.
public final class Terminal {
    /// The most scrollback lines a terminal accepts. It is far above what a
    /// session needs, and it stops a wrong number from asking for memory
    /// without limit.
    public static let maximumScrollbackLines = 1_000_000

    /// The most columns or rows a terminal accepts. A real window is far
    /// smaller. The bound keeps a wrong size from asking for gigabytes.
    public static let maximumGridDimension: UInt16 = 10_000

    let handle: GhosttyTerminal

    /// Creates an empty terminal.
    ///
    /// - Parameters:
    ///   - size: The grid size. Both values must be greater than zero and
    ///     at most `maximumGridDimension`.
    ///   - scrollbackLimit: The most lines of scrollback to keep, from zero to
    ///     `maximumScrollbackLines`. libghostty-vt prunes whole pages, so the
    ///     terminal can keep somewhat more lines.
    /// - Throws: `TerminalEmulationError` when a value is out of range.
    public convenience init(size: TerminalSize, scrollbackLimit: Int) throws {
        try Terminal.validate(size, in: "Terminal.init")
        var created: GhosttyTerminal?
        try TerminalEmulationError.check(
            ghostty_terminal_new(nil, &created, size.columns, size.rows),
            from: "ghostty_terminal_new"
        )
        try self.init(adopting: created, scrollbackLimit: scrollbackLimit)
    }

    /// Takes ownership of a libghostty-vt terminal.
    init(adopting created: GhosttyTerminal?, scrollbackLimit: Int) throws {
        guard let created else {
            throw TerminalEmulationError(function: "ghostty_terminal_new", resultCode: GHOSTTY_INVALID_VALUE.rawValue)
        }
        handle = created
        // A throw from here runs deinit, which frees the terminal once.
        try configure(scrollbackLimit: scrollbackLimit)
    }

    deinit {
        ghostty_terminal_free(handle)
    }

    /// The grid size.
    public var size: TerminalSize {
        TerminalSize(
            columns: (try? value(GHOSTTY_TERMINAL_DATA_COLS, as: UInt16.self)) ?? 0,
            rows: (try? value(GHOSTTY_TERMINAL_DATA_ROWS, as: UInt16.self)) ?? 0
        )
    }

    /// The cursor position in the active screen.
    public var cursorPosition: TerminalCursorPosition {
        TerminalCursorPosition(
            column: (try? value(GHOSTTY_TERMINAL_DATA_CURSOR_X, as: UInt16.self)) ?? 0,
            row: (try? value(GHOSTTY_TERMINAL_DATA_CURSOR_Y, as: UInt16.self)) ?? 0
        )
    }

    /// Whether a program switched to the alternate screen, as full-screen
    /// programs such as editors do.
    public var isAlternateScreenActive: Bool {
        let screen = try? value(GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, as: GhosttyTerminalScreen.self)
        return screen == GHOSTTY_TERMINAL_SCREEN_ALTERNATE
    }

    /// The number of lines that scrolled off the top of the primary screen.
    public var scrollbackLineCount: Int {
        (try? value(GHOSTTY_TERMINAL_DATA_SCROLLBACK_ROWS, as: Int.self)) ?? 0
    }

    /// Parses output bytes from the program in the terminal.
    ///
    /// A call can end inside an escape sequence or a UTF-8 character. The next
    /// call continues it.
    public func write(_ bytes: some ContiguousBytes) {
        bytes.withUnsafeBytes { buffer in
            guard !buffer.isEmpty else { return }
            parse(buffer)
        }
    }

    private func parse(_ buffer: UnsafeRawBufferPointer) {
        guard let start = buffer.baseAddress, !buffer.isEmpty else { return }
        ghostty_terminal_vt_write(handle, start.assumingMemoryBound(to: UInt8.self), buffer.count)
    }

    /// Parses text as UTF-8 output bytes.
    public func write(_ text: String) {
        write(Array(text.utf8))
    }


    /// Formats the active screen.
    public func formatted(_ format: ScreenFormat, extent: ScreenExtent = .visible) throws -> [UInt8] {
        var options = GhosttyFormatterTerminalOptions()
        options.size = MemoryLayout<GhosttyFormatterTerminalOptions>.size
        switch format {
        case .plainText:
            options.emit = GHOSTTY_FORMATTER_FORMAT_PLAIN
            options.trim = true
        case .virtualTerminalSequences:
            options.emit = GHOSTTY_FORMATTER_FORMAT_VT
            enableAllExtras(&options.extra)
        case .hypertextMarkup:
            options.emit = GHOSTTY_FORMATTER_FORMAT_HTML
        }

        switch extent {
        case .withScrollback:
            return try run(options)
        case .visible:
            var selection = try visibleSelection()
            return try withUnsafePointer(to: &selection) { pointer in
                options.selection = pointer
                return try run(options)
            }
        }
    }

    // MARK: - Private

    /// Refuses sizes that libghostty-vt cannot hold or that no window has.
    private static func validate(_ size: TerminalSize, in function: String) throws {
        guard (1...maximumGridDimension).contains(size.columns),
              (1...maximumGridDimension).contains(size.rows)
        else { throw TerminalEmulationError.invalidValue(in: function) }
    }

    /// The bottom right cell of a grid. An empty grid has none, and the
    /// subtraction would trap on an unsigned number.
    static func lastCell(of size: TerminalSize) throws -> GhosttyPointCoordinate {
        guard size.columns > 0, size.rows > 0 else {
            throw TerminalEmulationError.invalidValue(in: "Terminal.lastCell")
        }
        return GhosttyPointCoordinate(x: size.columns - 1, y: UInt32(size.rows - 1))
    }

    private func configure(scrollbackLimit: Int) throws {
        // A negative number would reach libghostty-vt as an enormous unsigned
        // one, and the byte limit that could stop it is removed below.
        guard (0...Terminal.maximumScrollbackLines).contains(scrollbackLimit) else {
            throw TerminalEmulationError.invalidValue(in: "Terminal.init")
        }
        // The default byte limit would hide the line limit, so remove it.
        try TerminalEmulationError.check(
            ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_BYTES, nil),
            from: "ghostty_terminal_set"
        )
        var lineLimit = scrollbackLimit
        try TerminalEmulationError.check(
            ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES, &lineLimit),
            from: "ghostty_terminal_set"
        )
    }

    private func value<Value>(_ data: GhosttyTerminalData, as type: Value.Type) throws -> Value {
        let storage = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { storage.deallocate() }
        try TerminalEmulationError.check(
            ghostty_terminal_get(handle, data, storage),
            from: "ghostty_terminal_get"
        )
        return storage.pointee
    }

    private func visibleSelection() throws -> GhosttySelection {
        let size = size
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        for (point, destination) in [
            (GhosttyPointCoordinate(x: 0, y: 0), \GhosttySelection.start),
            (try Terminal.lastCell(of: size), \GhosttySelection.end),
        ] {
            var reference = GhosttyGridRef()
            reference.size = MemoryLayout<GhosttyGridRef>.size
            var corner = GhosttyPoint()
            corner.tag = GHOSTTY_POINT_TAG_ACTIVE
            corner.value.coordinate = point
            try TerminalEmulationError.check(
                ghostty_terminal_grid_ref(handle, corner, &reference),
                from: "ghostty_terminal_grid_ref"
            )
            selection[keyPath: destination] = reference
        }
        return selection
    }

    private func enableAllExtras(_ extra: inout GhosttyFormatterTerminalExtra) {
        // Without these extras a restored screen would lose its colors,
        // modes, and tab stops.
        extra.size = MemoryLayout<GhosttyFormatterTerminalExtra>.size
        extra.palette = true
        extra.modes = true
        extra.scrolling_region = true
        extra.tabstops = true
        extra.pwd = true
        extra.keyboard = true
        extra.screen.size = MemoryLayout<GhosttyFormatterScreenExtra>.size
        extra.screen.cursor = true
        extra.screen.style = true
        extra.screen.hyperlink = true
        extra.screen.protection = true
        extra.screen.kitty_keyboard = true
        extra.screen.charsets = true
    }

    private func run(_ options: GhosttyFormatterTerminalOptions) throws -> [UInt8] {
        var formatter: GhosttyFormatter?
        try TerminalEmulationError.check(
            ghostty_formatter_terminal_new(nil, &formatter, handle, options),
            from: "ghostty_formatter_terminal_new"
        )
        defer { ghostty_formatter_free(formatter) }

        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        try TerminalEmulationError.check(
            ghostty_formatter_format_alloc(formatter, nil, &output, &length),
            from: "ghostty_formatter_format_alloc"
        )
        defer { ghostty_free(nil, output, length) }
        guard let output else { return [] }
        return Array(UnsafeBufferPointer(start: output, count: length))
    }
}
