import AppKit
import PaneAppearance

/// The rows of the first pane and their selection.
extension ProjectsListController: NSTableViewDataSource, NSTableViewDelegate {
    func configureTable() {
        table.dataSource = self
        table.delegate = self
        table.renameSelected = { [weak self] in self?.renameSelectedProject() }
        table.removeSelected = { [weak self] in self?.removeSelectedProject() }
        table.menu = contextMenu()
        configureDragging()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 8, right: 0)
        scroll.automaticallyAdjustsContentInsets = false
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ProjectCellView.identifier, owner: self) as? ProjectCellView ?? ProjectCellView()
        cell.show(rows[row])
        return cell
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SelectedRowView()
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isShowingChanges else { return }
        delegate?.projectsList(self, didSelect: selection)
    }
}
