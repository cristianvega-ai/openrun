/// The data behind the one user data pointer of a libghostty-vt terminal.
///
/// libghostty-vt gives every callback the same pointer, so each feature that
/// installs callbacks keeps its data here. The terminal owns the box and
/// frees it after the libghostty-vt terminal.
final class TerminalCallbackBox {
    /// The handler for the replies to queries. See `Terminal.setReplyHandler`.
    var reply: TerminalReplyBox?
    /// The handler for the bell, the title and render holds.
    var events: TerminalEventHandler?
    /// See `Terminal.reportedSize`.
    var reportedSize: TerminalSize?
}
