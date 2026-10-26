import GhosttyVt

/// The events of a terminal that a view shows: the bell, a new title, and
/// the start and end of a synchronized update (mode 2026).
///
/// A terminal calls these closures while it parses output, on the thread
/// that called `write`. They must not write to the same terminal.
public struct TerminalEventHandler {
    public var bell: () -> Void
    public var titleChanged: () -> Void
    /// Called with `true` when a program starts to hold the screen, and
    /// with `false` when it ends.
    public var renderHold: (Bool) -> Void

    public init(bell: @escaping () -> Void, titleChanged: @escaping () -> Void, renderHold: @escaping (Bool) -> Void) {
        self.bell = bell
        self.titleChanged = titleChanged
        self.renderHold = renderHold
    }
}

extension Terminal {
    private static func events(_ userdata: UnsafeMutableRawPointer?) -> TerminalEventHandler? {
        userdata.flatMap { Unmanaged<TerminalCallbackBox>.fromOpaque($0).takeUnretainedValue().events }
    }

    private static let bellCallback: GhosttyTerminalBellFn = { _, userdata in
        events(userdata)?.bell()
    }

    private static let titleCallback: GhosttyTerminalTitleChangedFn = { _, userdata in
        events(userdata)?.titleChanged()
    }

    private static let renderHoldCallback: GhosttyTerminalRenderHoldFn = { _, userdata, held in
        events(userdata)?.renderHold(held)
    }

    /// The title that the program set with OSC 0 or OSC 2, or an empty text.
    public var title: String {
        var text = GhosttyString()
        guard ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_TITLE, &text) == GHOSTTY_SUCCESS, let start = text.ptr else { return "" }
        return String(decoding: UnsafeBufferPointer(start: start, count: text.len), as: UTF8.self)
    }

    /// Installs the handler for the events, or removes it when `handler` is
    /// `nil`. It does not touch the reply handler of the terminal.
    public func setEventHandler(_ handler: TerminalEventHandler?) throws {
        // The handler is stored first, because a callback can run as soon as
        // libghostty-vt has it.
        callbackBox.events = handler
        let callbacks: [(GhosttyTerminalOption, UnsafeRawPointer)] = [
            (GHOSTTY_TERMINAL_OPT_BELL, unsafeBitCast(Self.bellCallback, to: UnsafeRawPointer.self)),
            (GHOSTTY_TERMINAL_OPT_TITLE_CHANGED, unsafeBitCast(Self.titleCallback, to: UnsafeRawPointer.self)),
            (GHOSTTY_TERMINAL_OPT_RENDER_HOLD, unsafeBitCast(Self.renderHoldCallback, to: UnsafeRawPointer.self)),
        ]
        for (option, function) in callbacks {
            let value: UnsafeRawPointer? = handler == nil ? nil : function
            try TerminalEmulationError.check(ghostty_terminal_set(handle, option, value), from: "ghostty_terminal_set")
        }
    }
}
