import TerminalEmulation

/// What a `TerminalView` tells its owner.
@MainActor
public protocol TerminalViewDelegate: AnyObject {
    /// The view requests a grid size after a change of window or text size.
    /// The owner passes the size to the session of the view.
    func terminalView(_ view: TerminalView, didChangeGridSize size: TerminalSize)

    /// The terminal applied a grid size after all earlier output.
    func terminalView(_ view: TerminalView, didApplyGridSize size: TerminalSize)

    /// The part of the grid that fits the view changed, even if the terminal size did not.
    func terminalView(_ view: TerminalView, didChangeVisibleGridSize size: TerminalSize)

    /// The program set a new title with OSC 0 or OSC 2. The owner shows it, or the folder of the session when the title is empty.
    func terminalView(_ view: TerminalView, didChangeTitle title: String)

    /// The user typed, pasted or moved the mouse, and the program must read
    /// these bytes. The owner writes them to the session.
    func terminalView(_ view: TerminalView, send bytes: [UInt8])

    /// The user pasted text with a line break, and the program has not turned on bracketed
    /// paste, so each line could run as a command. The owner asks the user.
    ///
    /// - Returns: `true` when the user wants the paste. The view pastes only after a yes.
    func terminalView(_ view: TerminalView, shouldPasteUnsafeText text: String) async -> Bool

    /// The user clicked a link that can open another app or a file. The owner asks before opening it.
    func terminalView(_ view: TerminalView, shouldOpenLink address: String) async -> Bool
}

public extension TerminalViewDelegate {
    func terminalView(_ view: TerminalView, shouldOpenLink address: String) async -> Bool { false }
    func terminalView(_ view: TerminalView, didChangeVisibleGridSize size: TerminalSize) {}
    func terminalView(_ view: TerminalView, didApplyGridSize size: TerminalSize) {}
}
