import Darwin
import GhosttyVt

/// Receives the bytes a terminal sends back to its program, such as the
/// answer to a cursor position query.
public typealias TerminalReplyHandler = (_ bytes: [UInt8]) -> Void

/// Holds the handler at a fixed address, so libghostty-vt can carry a plain
/// pointer to it. The terminal owns the box and frees it after the terminal.
final class TerminalReplyBox {
    let handler: TerminalReplyHandler
    /// Asked at each color-scheme query, because the appearance can change.
    let colorScheme: @Sendable () -> TerminalColorScheme

    /// The scheme whose colors are now the defaults of the terminal.
    var appliedScheme: TerminalColorScheme?
    /// How many bytes of `ESC [ 1 5 t` the end of the last write matched.
    private var matchedQueryBytes = 0

    init(handler: @escaping TerminalReplyHandler, colorScheme: @escaping @Sendable () -> TerminalColorScheme) {
        self.handler = handler
        self.colorScheme = colorScheme
    }

    private static let screenSizeQuery: [UInt8] = [0x1B, 0x5B, 0x31, 0x35, 0x74]

    /// Finds the end of the first `CSI 15 t` (the size of the screen in
    /// pixels) in the bytes, counting from the start of the bytes. The query
    /// can span two writes, so the box remembers a partial match.
    /// libghostty-vt does not parse this query at all, so nothing else can
    /// tell us about it.
    func endOfScreenSizeQuery(in bytes: UnsafeRawBufferPointer) -> Int? {
        var index = 0
        while index < bytes.count {
            if matchedQueryBytes == 0 {
                // Dense output holds few escapes, so jump to the next one.
                guard let base = bytes.baseAddress,
                      let found = memchr(base + index, 0x1B, bytes.count - index)
                else { return nil }
                index = base.distance(to: UnsafeRawPointer(found))
            }
            let byte = bytes[index]
            index += 1
            if byte == Self.screenSizeQuery[matchedQueryBytes] {
                matchedQueryBytes += 1
                if matchedQueryBytes == Self.screenSizeQuery.count {
                    matchedQueryBytes = 0
                    return index
                }
            } else {
                // An escape starts a new sequence wherever it comes.
                matchedQueryBytes = byte == 0x1B ? 1 : 0
            }
        }
        return nil
    }
}

extension Terminal {
    /// Whether the terminal answers the queries its program sends.
    ///
    /// A terminal answers nothing until a handler is installed. The session
    /// process installs one and writes the bytes to the pseudo terminal. A
    /// client that restores a snapshot installs none. Both terminals parse
    /// the same output, so a second handler would answer each query twice.
    public var hasReplyHandler: Bool {
        replyBox != nil
    }

    /// Installs the handler that receives the terminal's replies, or removes
    /// it when `handler` is `nil`.
    ///
    /// The terminal calls the handler while it parses output, on the thread
    /// that called `write`. The handler must not write to this terminal.
    ///
    /// Besides the cursor position and device attributes, the terminal answers
    /// the size queries (`CSI 14 t`, `16 t`, `18 t`, `19 t`) from its own grid,
    /// and the color-scheme query (`CSI ? 996 n`) from `colorScheme`.
    ///
    /// - Parameter colorScheme: The scheme to report. The default is the macOS
    ///   appearance of the current user.
    public func setReplyHandler(
        _ handler: TerminalReplyHandler?,
        colorScheme: @escaping @Sendable () -> TerminalColorScheme = { TerminalColorScheme.current() }
    ) throws {
        guard let handler else {
            let previous = replyBox
            try installCallbacks(userdata: nil, enabled: false)
            replyBox = nil
            clearDefaultColors()
            withExtendedLifetime(previous) {}
            return
        }
        try install(TerminalReplyBox(handler: handler, colorScheme: colorScheme))
    }

    /// Stores the box, then points libghostty-vt at it.
    ///
    /// The box must be stored first. If the install failed half way after a
    /// pointer was handed over, a box that nothing owns would leave
    /// libghostty-vt with a dangling pointer.
    /// - Parameter beforeInstalling: Runs between the two steps. Tests use it.
    func install(_ box: TerminalReplyBox, beforeInstalling: () -> Void = {}) throws {
        // The old box stays alive until libghostty-vt stopped using it.
        let previous = replyBox
        replyBox = box
        beforeInstalling()
        do {
            try installCallbacks(userdata: Unmanaged.passUnretained(box).toOpaque(), enabled: true)
        } catch {
            // Take the callbacks back. When that fails too, libghostty-vt may
            // still hold the pointer, so the box stays stored and alive.
            if (try? installCallbacks(userdata: nil, enabled: false)) != nil {
                replyBox = nil
            }
            withExtendedLifetime(previous) {}
            throw error
        }
        withExtendedLifetime(previous) {}
    }

    /// Answers `CSI 15 t` from the nominal cell, like the other size queries.
    func answerScreenSizeQuery(for box: TerminalReplyBox) {
        let grid = size
        let height = UInt32(grid.rows) * Self.nominalCellHeight
        let width = UInt32(grid.columns) * Self.nominalCellWidth
        box.handler(Array("\u{1B}[5;\(height);\(width)t".utf8))
    }

    /// Sets the default foreground and background to the colors of the
    /// appearance, when the appearance changed. Programs ask for them with
    /// OSC 10 and OSC 11, and libghostty-vt answers from these defaults.
    ///
    /// A default color is a setting of the terminal, not output. The snapshot
    /// carries it, but the picture of `openrun attach` and the text of
    /// `openrun read` do not: tests compare them with and without the colors.
    func applyDefaultColors(for box: TerminalReplyBox) {
        let scheme = box.colorScheme()
        guard scheme != box.appliedScheme else { return }
        var foreground = scheme == .dark ? GhosttyColorRgb(r: 255, g: 255, b: 255) : GhosttyColorRgb(r: 0, g: 0, b: 0)
        var background = scheme == .dark ? GhosttyColorRgb(r: 0, g: 0, b: 0) : GhosttyColorRgb(r: 255, g: 255, b: 255)
        // A failure leaves the old colors, and the next write tries again.
        guard ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, &foreground) == GHOSTTY_SUCCESS,
              ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, &background) == GHOSTTY_SUCCESS
        else { return }
        box.appliedScheme = scheme
    }

    private func clearDefaultColors() {
        _ = ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, nil)
        _ = ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, nil)
    }

    // MARK: - Private

    private static let replyWriteCallback: GhosttyTerminalWritePtyFn = { _, userdata, bytes, length in
        guard let userdata, let bytes, length > 0 else { return }
        let box = Unmanaged<TerminalReplyBox>.fromOpaque(userdata).takeUnretainedValue()
        box.handler(Array(UnsafeBufferPointer(start: bytes, count: length)))
    }

    // libghostty-vt answers a device attributes query only when it can ask
    // for the answer, so a handler alone would leave these queries silent.
    private static let deviceAttributesCallback: GhosttyTerminalDeviceAttributesFn = { _, _, attributes in
        guard let attributes else { return false }
        attributes.pointee = GhosttyDeviceAttributes()
        // Level 2 with ANSI color: it matches what the screen can show and
        // makes programs expect nothing newer.
        attributes.pointee.primary.conformance_level = UInt16(GHOSTTY_DA_CONFORMANCE_LEVEL_2)
        attributes.pointee.primary.features.0 = UInt16(GHOSTTY_DA_FEATURE_ANSI_COLOR)
        attributes.pointee.primary.num_features = 1
        attributes.pointee.secondary.device_type = UInt16(GHOSTTY_DA_DEVICE_TYPE_VT220)
        return true
    }

    /// A cell is a fixed size of pixels, because a session has no window.
    /// Programs use the size to scale images, and any plausible cell works.
    static let nominalCellWidth: UInt32 = 8
    static let nominalCellHeight: UInt32 = 16

    // Like device attributes, the size queries (and the in-band size reports
    // of mode 2048) are answered only when this callback fills in a size.
    private static let sizeCallback: GhosttyTerminalSizeFn = { terminal, _, size in
        guard let terminal, let size else { return false }
        var columns: UInt16 = 0
        var rows: UInt16 = 0
        guard ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_COLS, &columns) == GHOSTTY_SUCCESS,
              ghostty_terminal_get(terminal, GHOSTTY_TERMINAL_DATA_ROWS, &rows) == GHOSTTY_SUCCESS
        else { return false }
        size.pointee = GhosttySizeReportSize(
            rows: rows,
            columns: columns,
            cell_width: nominalCellWidth,
            cell_height: nominalCellHeight
        )
        return true
    }

    private static let colorSchemeCallback: GhosttyTerminalColorSchemeFn = { _, userdata, scheme in
        guard let userdata, let scheme else { return false }
        let box = Unmanaged<TerminalReplyBox>.fromOpaque(userdata).takeUnretainedValue()
        scheme.pointee = box.colorScheme() == .dark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
        return true
    }

    /// Sets or clears every callback that answers a query.
    private func installCallbacks(userdata: UnsafeMutableRawPointer?, enabled: Bool) throws {
        // Clear the callbacks before the userdata changes, so none runs with
        // a pointer to a box that is gone.
        let callbacks: [(GhosttyTerminalOption, UnsafeRawPointer)] = [
            (GHOSTTY_TERMINAL_OPT_WRITE_PTY, unsafeBitCast(Self.replyWriteCallback, to: UnsafeRawPointer.self)),
            (GHOSTTY_TERMINAL_OPT_DEVICE_ATTRIBUTES, unsafeBitCast(Self.deviceAttributesCallback, to: UnsafeRawPointer.self)),
            (GHOSTTY_TERMINAL_OPT_SIZE, unsafeBitCast(Self.sizeCallback, to: UnsafeRawPointer.self)),
            (GHOSTTY_TERMINAL_OPT_COLOR_SCHEME, unsafeBitCast(Self.colorSchemeCallback, to: UnsafeRawPointer.self)),
        ]
        for (option, _) in callbacks {
            try TerminalEmulationError.check(ghostty_terminal_set(handle, option, nil), from: "ghostty_terminal_set")
        }
        try TerminalEmulationError.check(
            ghostty_terminal_set(handle, GHOSTTY_TERMINAL_OPT_USERDATA, userdata),
            from: "ghostty_terminal_set"
        )
        guard enabled else { return }
        for (option, function) in callbacks {
            try TerminalEmulationError.check(ghostty_terminal_set(handle, option, function), from: "ghostty_terminal_set")
        }
    }
}
