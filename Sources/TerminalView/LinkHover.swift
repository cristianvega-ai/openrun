import AppKit
import TerminalEmulation

/// What the view shows while Command is down over a link: a pointing hand,
/// and an underline under a plain web address. It looks for the address only
/// when the pointer moves to another cell, Command changes, or the text changes.
@MainActor
final class LinkHover {
    private let terminal: Terminal
    /// The plain address under the pointer, which the renderer underlines.
    private(set) var link: PlainLink?
    /// Whether a Command-click would open a link here, so the pointer is a hand.
    private(set) var isOverLink = false
    /// The cell under the pointer while Command is down, or `nil`.
    private var cell: ViewportCell?

    init(terminal: Terminal) {
        self.terminal = terminal
    }

    /// Whether Command is down over the view, so a change of the text can change the link.
    var isActive: Bool { cell != nil }

    /// - Parameters:
    ///   - cell: The cell under the pointer, or `nil` when the pointer is outside the grid.
    ///   - textChanged: The text or the viewport changed, so the same cell can hold another link.
    /// - Returns: `true` when the link or the pointer changed.
    func update(modifiers: NSEvent.ModifierFlags, at cell: ViewportCell?, textChanged: Bool = false) -> Bool {
        let cell = modifiers.contains(.command) ? cell : nil
        guard cell != self.cell || (textChanged && cell != nil) else { return false }
        self.cell = cell
        var link: PlainLink?, isOverLink = false
        if let cell {
            if let address = terminal.hyperlink(at: cell) {
                isOverLink = LinkSchemeRule.target(for: address) != nil
            } else if let found = PlainLinkFinder.link(at: cell, in: terminal) {
                (link, isOverLink) = (found, true)
            }
        }
        defer { (self.link, self.isOverLink) = (link, isOverLink) }
        return link != self.link || isOverLink != self.isOverLink
    }
}
