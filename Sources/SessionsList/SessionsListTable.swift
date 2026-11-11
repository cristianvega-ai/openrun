import AppKit
import PaneAppearance

/// The rows of the second pane and their selection.
extension SessionsListController: NSTableViewDataSource, NSTableViewDelegate {
    func configureTable() {
        table.dataSource = self
        table.delegate = self
        table.openSelected = { [weak self] in
            guard let self, let selection else { return }
            delegate?.sessionsList(self, didOpen: selection)
        }
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 8, right: 0)
        scroll.automaticallyAdjustsContentInsets = false
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: SessionCellView.identifier, owner: self) as? SessionCellView ?? SessionCellView()
        cell.show(rows[row])
        return cell
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SelectedRowView()
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isShowingChanges else { return }
        delegate?.sessionsList(self, didSelect: selection)
    }
}
