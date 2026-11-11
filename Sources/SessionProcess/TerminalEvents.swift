import TerminalEmulation

/// What the terminal of a session reported while it parsed a piece of
/// output: the bell, a new title, and a desktop notification.
///
/// The terminal calls its handler during `write`, on the session's context,
/// and a handler must not write to the terminal. So the handler only notes
/// the events here, and the session takes them after the piece.
final class TerminalEvents {
    private(set) var bellRang = false
    private(set) var titleChanged = false
    /// The text of the last notification. A piece of output can hold many,
    /// and only the last one counts.
    private(set) var notification: String?

    var handler: TerminalEventHandler {
        TerminalEventHandler(
            bell: { [weak self] in self?.bellRang = true },
            titleChanged: { [weak self] in self?.titleChanged = true },
            renderHold: { _ in },
            // OSC 777 names its sender in the title, such as "Claude Code",
            // and says what it wants in the body.
            desktopNotification: { [weak self] title, body in self?.notification = body.isEmpty ? title : body }
        )
    }

    func note(notification text: String) {
        notification = text
    }

    func reset() {
        (bellRang, titleChanged, notification) = (false, false, nil)
    }
}
