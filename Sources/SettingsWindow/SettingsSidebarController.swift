import AppKit
import PaneAppearance

/// The left part of the settings window: the search field, and the list
/// of the panes in groups, with a line between two groups.
@MainActor final class SettingsSidebarController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    static let width: CGFloat = 216
    /// The rows of the list: the index of a pane, or `nil` for the line
    /// between two groups.
    let items: [Int?]
    private let panes: [SettingsPane]
    let searchField = NSSearchField()
    let table = NSTableView()
    /// Tells the index of the pane that the user chose.
    var chose: ((Int) -> Void)?
    /// Tells the text of the search field after each change.
    var searched: ((String) -> Void)?

    init(groups: [[SettingsPane]]) {
        panes = groups.flatMap { $0 }
        var items: [Int?] = []
        for group in groups {
            let first = items.compactMap { $0 }.count
            items += (items.isEmpty ? [] : [nil]) + group.indices.map { first + $0 }
        }
        self.items = items
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let root = PaneBackgroundView(color: PaneColor.firstPane), topRow = PaneTopRow(background: PaneColor.firstPane), scroll = OverlayScrollView()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane")))
        (table.headerView, table.backgroundColor, table.style, table.intercellSpacing) = (nil, .clear, .fullWidth, .zero)
        (table.dataSource, table.delegate, table.allowsEmptySelection, table.focusRingType) = (self, self, true, .none)
        (scroll.documentView, scroll.drawsBackground) = (table, false)
        (searchField.placeholderString, searchField.target, searchField.action) = ("Search", self, #selector(search))
        searchField.sendsSearchStringImmediately = true
        for view in [topRow, searchField, scroll] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: root.topAnchor), topRow.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            topRow.trailingAnchor.constraint(equalTo: root.trailingAnchor), searchField.topAnchor.constraint(equalTo: topRow.bottomAnchor),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14), searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            root.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        view = root
    }

    /// Selects the row of a pane. This also tells `chose`.
    func select(pane index: Int) {
        loadViewIfNeeded()
        items.firstIndex(of: index).map { table.selectRowIndexes([$0], byExtendingSelection: false) }
    }

    /// A search shows rows of many panes, so no pane has the selection.
    @objc func search() {
        if !searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty { table.deselectAll(nil) }
        searched?(searchField.stringValue)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let pane = items[row] else { return Self.groupLine() }
        return SettingsSidebarCellView(title: panes[pane].title, symbolName: panes[pane].symbolName)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SelectedRowView() }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { items[row] == nil ? 17 : SettingsSidebarCellView.height }

    /// A line takes no selection. An arrow key goes on to the pane after it.
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        guard let row = proposed.first, items.indices.contains(row), items[row] == nil else { return proposed }
        let next = row + (row > tableView.selectedRow ? 1 : -1)
        return NSApplication.shared.currentEvent?.type == .keyDown && items.indices.contains(next) ? IndexSet(integer: next) : tableView.selectedRowIndexes
    }

    /// The choice of a pane ends a search.
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard items.indices.contains(table.selectedRow), let pane = items[table.selectedRow] else { return }
        searchField.stringValue = ""
        chose?(pane)
    }

    private static func groupLine() -> NSView {
        let cell = NSView(), line = SettingRowsView.line()
        line.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(line)
        NSLayoutConstraint.activate([
            line.centerYAnchor.constraint(equalTo: cell.centerYAnchor), line.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 18),
            line.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -18),
        ])
        return cell
    }
}
