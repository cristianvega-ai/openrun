import AppKit
import TerminalEmulation

/// Opens a link with a Command-click: a link of OSC 8, or a plain `http` or
/// `https` address in the text (`PlainLinkFinder`). When Command is down at the
/// press of the left button over a link, the link wins for the whole click: the
/// press, the drag and the release do not go to the program or to the selection,
/// also when the program reads the mouse. Agents turn mouse reports on, and their
/// links must still work.
@MainActor
final class LinkClick {
    var opener: any LinkOpener = WorkspaceLinkOpener()
    /// A host that shows web pages itself takes a web link here. It
    /// returns false when it does not take the link, and the link then
    /// opens with the default program.
    var webLinkAction: ((URL) -> Bool)?
    /// The window asks before a link opens an app or a file.
    var ask: @MainActor (String) async -> Bool = { _ in false }
    private let terminal: Terminal
    /// The address of the link that the click started on, or `nil` when no link click is going on.
    private var pressedAddress: String?

    init(terminal: Terminal) {
        self.terminal = terminal
    }

    /// Whether a link click is going on. Its drag does not go anywhere else.
    var isActive: Bool { pressedAddress != nil }

    /// The address of the link at a cell. A link of OSC 8 wins over the text under it.
    func address(at cell: ViewportCell) -> String? {
        terminal.hyperlink(at: cell) ?? PlainLinkFinder.link(at: cell, in: terminal)?.address
    }

    /// - Returns: `true` when the press is the start of a link click.
    func press(modifiers: NSEvent.ModifierFlags, at cell: ViewportCell) -> Bool {
        guard modifiers.contains(.command), let address = address(at: cell), LinkSchemeRule.target(for: address) != nil else { return false }
        pressedAddress = address
        return true
    }

    /// Ends the click. The link opens when the pointer is still over it.
    func release(at cell: ViewportCell) {
        defer { pressedAddress = nil }
        guard let address = pressedAddress, self.address(at: cell) == address else { return }
        open(address)
    }

    /// Opens a link at once, or after a yes for a scheme that can open another app
    /// or a file. An address that is not valid opens nothing.
    func open(_ address: String) {
        guard let target = LinkSchemeRule.target(for: address) else { return }
        guard LinkSchemeRule.needsQuestion(for: target) else {
            let isWebLink = ["http", "https"].contains(target.scheme?.lowercased() ?? "")
            if !isWebLink || webLinkAction?(target) != true { opener.open(target) }
            return
        }
        let (ask, opener) = (ask, opener)
        Task { if await ask(address) { opener.open(target) } }
    }
}
