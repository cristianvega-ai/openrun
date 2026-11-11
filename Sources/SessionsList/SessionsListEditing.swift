import AppKit

/// The rename in place and the close of a row, from its context menu.
extension SessionsListController: NSTextFieldDelegate {
    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Rename", action: #selector(renameClickedRow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Close", action: #selector(closeClickedRow), keyEquivalent: "").target = self
        return menu
    }

    /// Starts the edit of the title of a row in place.
    public func beginRename(of identifier: UUID) {
        guard let index = rows.firstIndex(where: { $0.identifier == identifier }) else { return }
        table.scrollRowToVisible(index)
        guard let cell = table.view(atColumn: 0, row: index, makeIfNecessary: true) as? SessionCellView else { return }
        cell.title.isEditable = true
        cell.title.delegate = self
        view.window?.makeFirstResponder(cell.title)
    }

    @objc func renameClickedRow() {
        if rows.indices.contains(table.clickedRow) { beginRename(of: rows[table.clickedRow].identifier) }
    }

    @objc func closeClickedRow() {
        closeRow(at: table.clickedRow)
    }

    func closeRow(at index: Int) {
        if rows.indices.contains(index) { delegate?.sessionsList(self, didClose: rows[index].identifier) }
    }

    /// Escape ends the edit and keeps the old title.
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        let row = table.row(for: control)
        if rows.indices.contains(row) { control.stringValue = rows[row].title }
        view.window?.makeFirstResponder(table)
        return true
    }

    /// A new title that is not empty goes to the host, and the row shows it
    /// once the host has it. An empty title keeps the old one.
    public func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        field.isEditable = false
        let row = table.row(for: field)
        guard rows.indices.contains(row) else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == rows[row].title {
            field.stringValue = rows[row].title
        } else {
            delegate?.sessionsList(self, didRename: rows[row].identifier, to: name)
        }
        if view.window?.firstResponder !== table { view.window?.makeFirstResponder(table) }
    }
}
