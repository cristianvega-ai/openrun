import AppKit
import ListUpdates
import PaneAppearance

/// The second pane: the threads with agents and the terminal sessions of
/// the entry that the first pane selects, as vertical tabs. It shows display
/// values, filters and orders them, and reports what the user does through
/// its delegate.
@MainActor
public final class SessionsListController: NSObject {
    /// The pane: its top row over the list, on the color of the second pane.
    public let view = PaneBackgroundView(color: PaneColor.secondPane)
    public let topRow = PaneTopRow(background: PaneColor.secondPane)
    public weak var delegate: SessionsListDelegate?
    public internal(set) var content = SessionsListContent()
    public internal(set) var filter = SessionsFilter.all
    public internal(set) var order = SessionsOrder.manual
    let titleLabel = NSTextField(labelWithString: "")
    let filterLabel = NSTextField(labelWithString: "")
    let arrangementButton: NSButton
    let newSessionButton: NSButton
    let table = SessionsTableView()
    let emptyView = SessionsEmptyView()
    let scroll = NSScrollView()
    var rows: [SessionsListRow] = []
    /// The time for the ages of the rows. Tests set it.
    var now: () -> Date = { Date() }
    /// The table changes its selection while it shows a change, and that is no choice of the user.
    var isShowingChanges = false

    public override init() {
        arrangementButton = PaneButton.make(symbol: "line.3.horizontal.decrease", label: "Filter and Order", target: nil, action: nil)
        newSessionButton = PaneButton.make(symbol: "square.and.pencil", label: "New Session", target: nil, action: nil)
        super.init()
        (arrangementButton.target, arrangementButton.action) = (self, #selector(showArrangementMenu))
        (newSessionButton.target, newSessionButton.action) = (self, #selector(showNewSessionMenu))
        (emptyView.startButton.target, emptyView.startButton.action) = (self, #selector(showNewSessionMenu))
        configureTopRow()
        configureTable()
        layOut()
    }

    /// The view that takes the keyboard focus when the pane gets it.
    public var focusView: NSView { table }

    /// The selected row, if the list shows it.
    public var selection: UUID? {
        rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].identifier : nil
    }

    /// Shows new content. Only the rows that changed update, and the
    /// selection stays on its row while the list shows the row.
    public func show(_ content: SessionsListContent) {
        self.content = content
        update()
    }

    /// Sets the filter and the order, such as the ones of the last start,
    /// without a report to the delegate.
    public func arrange(filter: SessionsFilter, order: SessionsOrder) {
        (self.filter, self.order) = (filter, order)
        update()
    }

    /// Selects a row without a report to the delegate.
    public func select(_ identifier: UUID?) {
        isShowingChanges = true
        defer { isShowingChanges = false }
        guard let index = rows.firstIndex(where: { $0.identifier == identifier }) else { return table.deselectAll(nil) }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }

    /// Makes the rows again from the content, the filter, the order and the time.
    func update() {
        updateTopRow()
        let selected = selection
        let newRows = order.arranged(content.rows.filter(filter.includes)).map { SessionsListRow($0, now: now()) }
        let changes = RowChanges(from: rows, to: newRows) { $0.identifier }
        rows = newRows
        isShowingChanges = true
        changes.apply(to: table) { index in
            (table.view(atColumn: 0, row: index, makeIfNecessary: false) as? SessionCellView)?.show(rows[index])
        }
        isShowingChanges = false
        emptyView.message.stringValue = SessionsEmptyView.message(for: filter)
        emptyView.isHidden = !rows.isEmpty
        guard selection != selected else { return }
        select(selected)
        if selection != selected { delegate?.sessionsList(self, didSelect: selection) }
    }

    private func layOut() {
        topRow.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        view.addSubview(emptyView)
        view.addSubview(topRow)
        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: view.topAnchor),
            topRow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topRow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topRow.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyView.topAnchor.constraint(equalTo: topRow.bottomAnchor),
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
