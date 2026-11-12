import GhosttyVt

/// The events of a terminal that a view shows: the bell, a new title, the
/// start and end of a synchronized update (mode 2026), and a request for a
/// desktop notification.
///
/// A terminal calls these closures while it parses output, on the thread
/// that called `write`. They must not write to the same terminal.
public struct TerminalEventHandler {
    public var bell: () -> Void
    public var titleChanged: () -> Void
    /// Called with `true` when a program starts to hold the screen, and
    /// with `false` when it ends.
    public var renderHold: (Bool) -> Void
    /// Called with the title and the body of a notification that the
    /// program asks for with OSC 9 or OSC 777. The title is empty when the
    /// sequence has none. libghostty-vt takes OSC 9 ; 4 and the other
    /// commands of ConEmu as what they are, so they never come here, and
    /// neither does OSC 99 of kitty. Each text holds
    /// at most `notificationByteLimit` bytes of the program, which it chose.
    public var desktopNotification: (_ title: String, _ body: String) -> Void
    /// Called with the plain text that a program wants on the clipboard
    /// of the user (OSC 52 and the like). It returns whether the text
    /// went there. A terminal with no place for it, such as the one of
    /// the session process, takes the default, which refuses.
    public var clipboardWrite: (_ text: String) -> Bool

    /// The most bytes of text that a program can put on the clipboard.
    public static let clipboardByteLimit = 1024 * 1024

    /// The most bytes of a title or a body that a notification passes on.
    /// libghostty-vt drops a command of more than about 2 KiB itself.
    public static let notificationByteLimit = 2048

    public init(
        bell: @escaping () -> Void, titleChanged: @escaping () -> Void, renderHold: @escaping (Bool) -> Void,
        desktopNotification: @escaping (_ title: String, _ body: String) -> Void = { _, _ in },
        clipboardWrite: @escaping (_ text: String) -> Bool = { _ in false }
    ) {
        self.bell = bell
        self.titleChanged = titleChanged
        self.renderHold = renderHold
        self.desktopNotification = desktopNotification
        self.clipboardWrite = clipboardWrite
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

    private static let desktopNotificationCallback: GhosttyTerminalDesktopNotificationFn = { _, userdata, notification in
        // The structure has a size, so a newer library can make it larger.
        let end = MemoryLayout<GhosttyTerminalDesktopNotification>.offset(of: \.body)! + MemoryLayout<GhosttyString>.size
        guard let notification, notification.pointee.size >= end, let handler = events(userdata) else { return }
        handler.desktopNotification(boundedText(notification.pointee.title), boundedText(notification.pointee.body))
    }

    /// Takes only plain text for the standard clipboard. A request with
    /// no content would empty the clipboard of the user, so it is refused.
    private static let clipboardWriteCallback: GhosttyTerminalClipboardWriteFn = { _, userdata, write in
        guard let write, let handler = events(userdata) else { return }
        let request = write.pointee
        var result = GHOSTTY_CLIPBOARD_WRITE_RESULT_UNSUPPORTED
        if request.location == GHOSTTY_CLIPBOARD_LOCATION_STANDARD, let text = plainText(of: request) {
            result = handler.clipboardWrite(text) ? GHOSTTY_CLIPBOARD_WRITE_RESULT_SUCCESS : GHOSTTY_CLIPBOARD_WRITE_RESULT_DENIED
        }
        var reply = GhosttyClipboardWriteReply(size: MemoryLayout<GhosttyClipboardWriteReply>.size, result: result, remember: false)
        request.reply?(write, &reply)
    }

    /// The plain text of a clipboard write, when it has one within the limit.
    private static func plainText(of request: GhosttyClipboardWrite) -> String? {
        guard let contents = request.contents else { return nil }
        for content in UnsafeBufferPointer(start: contents, count: request.contents_len) {
            guard let mime = content.mime.ptr, let data = content.data.ptr, content.data.len <= TerminalEventHandler.clipboardByteLimit else { continue }
            let kind = String(decoding: UnsafeBufferPointer(start: mime, count: content.mime.len), as: UTF8.self)
            if kind.hasPrefix("text/plain") { return String(decoding: UnsafeBufferPointer(start: data, count: content.data.len), as: UTF8.self) }
        }
        return nil
    }

    private static func boundedText(_ text: GhosttyString) -> String {
        guard let start = text.ptr else { return "" }
        let bytes = UnsafeBufferPointer(start: start, count: min(text.len, TerminalEventHandler.notificationByteLimit))
        return String(decoding: bytes, as: UTF8.self)
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
            (GHOSTTY_TERMINAL_OPT_DESKTOP_NOTIFICATION, unsafeBitCast(Self.desktopNotificationCallback, to: UnsafeRawPointer.self)),
            (GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE, unsafeBitCast(Self.clipboardWriteCallback, to: UnsafeRawPointer.self)),
        ]
        for (option, function) in callbacks {
            let value: UnsafeRawPointer? = handler == nil ? nil : function
            try TerminalEmulationError.check(ghostty_terminal_set(handle, option, value), from: "ghostty_terminal_set")
        }
    }
}
