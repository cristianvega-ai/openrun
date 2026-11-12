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
        guard rows[row].entry != nil else {
            let cell = tableView.makeView(withIdentifier: ProjectsHeadingCellView.identifier, owner: self) as? ProjectsHeadingCellView ?? ProjectsHeadingCellView()
            cell.show(rows[row])
            return cell
        }
        let cell = tableView.makeView(withIdentifier: ProjectCellView.identifier, owner: self) as? ProjectCellView ?? ProjectCellView()
        cell.show(rows[row])
        return cell
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SelectedRowView()
    }

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row].kind {
        case .entry: ProjectCellView.height
        case .heading: ProjectsHeadingCellView.headingHeight
        case .hint: ProjectsHeadingCellView.hintHeight
        }
    }

    /// The heading and the hint take no selection. An arrow key goes on to
    /// the entry after them, and a click on them keeps the selection.
    public func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        guard let row = proposed.first, rows.indices.contains(row), rows[row].entry == nil else { return proposed }
        let next = row + (row > tableView.selectedRow ? 1 : -1)
        let isKey = NSApp.currentEvent?.type == .keyDown
        return isKey && rows.indices.contains(next) && rows[next].entry != nil ? IndexSet(integer: next) : tableView.selectedRowIndexes
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isShowingChanges else { return }
        delegate?.projectsList(self, didSelect: selection)
    }
}
