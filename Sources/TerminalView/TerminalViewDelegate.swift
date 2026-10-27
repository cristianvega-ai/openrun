import TerminalEmulation

/// What a `TerminalView` tells its owner.
@MainActor
public protocol TerminalViewDelegate: AnyObject {
    /// The grid has a new size, because the view changed its size or its text
    /// size. The owner passes the size on to the session of the view.
    func terminalView(_ view: TerminalView, didChangeGridSize size: TerminalSize)
}
