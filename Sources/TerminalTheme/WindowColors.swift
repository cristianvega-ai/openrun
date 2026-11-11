import TerminalEmulation

/// The colors of the window around the terminal, so that a theme colors the
/// whole window as one (decision of 2026-10-12). The lists of the first and
/// the second pane draw their text and their selection with them.
public struct WindowColors: Equatable, Sendable {
    /// The background of the first pane, the projects.
    public var firstPane: TerminalColor
    /// The background of the second pane, the sessions.
    public var secondPane: TerminalColor
    /// The lines between the panes and under their top rows.
    public var divider: TerminalColor
    /// The first line of a row, such as a title.
    public var text: TerminalColor
    /// The second line of a row, counts and icons: quieter than `text`.
    public var quietText: TerminalColor
    /// The soft rounded rectangle behind the selected row in a key window.
    public var rowSelection: TerminalColor
    /// The selected row when the window is not key: quieter still.
    public var inactiveRowSelection: TerminalColor
    /// The mark of a row that needs the user, the only strong color of the lists.
    public var attention: TerminalColor

    init(firstPane: UInt32, secondPane: UInt32, divider: UInt32, text: UInt32, quietText: UInt32, rowSelection: UInt32, inactiveRowSelection: UInt32, attention: UInt32) {
        self.firstPane = TerminalColor(hexadecimal: firstPane)
        self.secondPane = TerminalColor(hexadecimal: secondPane)
        self.divider = TerminalColor(hexadecimal: divider)
        self.text = TerminalColor(hexadecimal: text)
        self.quietText = TerminalColor(hexadecimal: quietText)
        self.rowSelection = TerminalColor(hexadecimal: rowSelection)
        self.inactiveRowSelection = TerminalColor(hexadecimal: inactiveRowSelection)
        self.attention = TerminalColor(hexadecimal: attention)
    }
}
