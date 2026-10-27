import AppKit
import TerminalEmulation

/// Opens the links of OSC 8 with a Command-click. When Command is down at the
/// press of the left button over a link, the link wins for the whole click: the
/// press, the drag and the release do not go to the program or to the selection,
/// also when the program reads the mouse. Agents turn mouse reports on, and their
/// links must still work.
@MainActor
final class LinkClick {
    var opener: any LinkOpener = WorkspaceLinkOpener()
    private let terminal: Terminal
    /// The address of the link that the click started on, or `nil` when no link click is going on.
    private var pressedAddress: String?

    init(terminal: Terminal) {
        self.terminal = terminal
    }

    /// Whether a link click is going on. Its drag does not go anywhere else.
    var isActive: Bool { pressedAddress != nil }

    /// - Returns: `true` when the press is the start of a link click.
    func press(modifiers: NSEvent.ModifierFlags, at cell: ViewportCell) -> Bool {
        guard modifiers.contains(.command), let address = terminal.hyperlink(at: cell), URL(string: address) != nil else { return false }
        pressedAddress = address
        return true
    }

    /// Ends the click. The link opens when the pointer is still over it.
    func release(at cell: ViewportCell) {
        defer { pressedAddress = nil }
        guard let address = pressedAddress, terminal.hyperlink(at: cell) == address, let url = URL(string: address) else { return }
        opener.open(url)
    }
}
