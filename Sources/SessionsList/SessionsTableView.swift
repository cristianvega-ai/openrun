import AppKit

/// The table of the second pane: one column of rows of one height, with no
/// header, on the color of the pane. Return opens the selected row: the
/// keyboard focus goes to its content in the third pane.
@MainActor
final class SessionsTableView: NSTableView {
    var openSelected: (() -> Void)?

    init() {
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Session"))
        column.resizingMask = .autoresizingMask
        addTableColumn(column)
        headerView = nil
        style = .plain
        rowSizeStyle = .custom
        rowHeight = SessionCellView.height
        intercellSpacing = .zero
        backgroundColor = .clear
        focusRingType = .none
        columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        setAccessibilityLabel("Sessions")
    }

    required init?(coder: NSCoder) {
        fatalError("SessionsTableView does not come from a storyboard.")
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if [36, 76].contains(event.keyCode), modifiers.isEmpty, selectedRow >= 0 {
            openSelected?()
        } else {
            super.keyDown(with: event)
        }
    }

    /// The context menu belongs to the row under the pointer, so a click on
    /// the empty part of the list opens no menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        row(at: convert(event.locationInWindow, from: nil)) >= 0 ? super.menu(for: event) : nil
    }
}
