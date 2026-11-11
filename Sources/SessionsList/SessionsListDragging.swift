import AppKit

/// A drag of a row to another place in the user's own order. In the other
/// orders the place of a row follows from its facts, so a drag moves nothing.
extension SessionsListController {
    static let rowType = NSPasteboard.PasteboardType("ai.cristianvega.openrun.session-row")

    func configureDragging() {
        table.registerForDraggedTypes([Self.rowType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.draggingDestinationFeedbackStyle = .gap
    }

    public func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard order == .manual else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.rowType)
        return item
    }

    public func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard let source = draggedRow(info), move(row: source, dropRow: row) != nil else { return [] }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    public func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let source = draggedRow(info) else { return false }
        return moveRow(row: source, dropRow: row)
    }

    /// Moves the row at once, so the drop does not jump back while the host
    /// keeps the new order, and then tells the host.
    func moveRow(row: Int, dropRow: Int) -> Bool {
        guard let move = move(row: row, dropRow: dropRow), let source = content.rows.firstIndex(where: { $0.identifier == move.identifier }) else { return false }
        content.rows.insert(content.rows.remove(at: source), at: move.destination)
        update()
        delegate?.sessionsList(self, didMove: move.identifier, toIndex: move.destination)
        return true
    }

    private func move(row: Int, dropRow: Int) -> SessionRowMove? {
        guard order == .manual else { return nil }
        return SessionRowMove(order: content.rows.map(\.identifier), visible: rows.map(\.identifier), row: row, dropRow: dropRow)
    }

    private func draggedRow(_ info: NSDraggingInfo) -> Int? {
        guard (info.draggingSource as? NSTableView) === table else { return nil }
        return info.draggingPasteboard.string(forType: Self.rowType).flatMap(Int.init)
    }
}
