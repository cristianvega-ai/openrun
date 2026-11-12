import AppKit
import ListUpdates
import PaneAppearance

/// The first pane: "All Projects", "Needs You", and under the heading
/// "Projects" the projects in the user's order. It
/// shows display values and reports what the user does through its delegate.
@MainActor
public final class ProjectsListController: NSObject {
    /// The pane: its top row over the list, on the color of the first pane.
    public let view = PaneBackgroundView(color: PaneColor.firstPane)
    /// The top row holds the add button. The host makes room in it for the traffic lights.
    public let topRow = PaneTopRow(background: PaneColor.firstPane)
    public weak var delegate: ProjectsListDelegate?
    public internal(set) var content = ProjectsListContent()
    let table = ProjectsTableView()
    let scroll = OverlayScrollView()
    let usage = AccountUsageView()
    let addButton: NSButton
    var rows = ProjectsListRow.rows(for: ProjectsListContent())
    /// The table selects a row while it shows a change, and that is no choice of the user.
    var isShowingChanges = false

    public override init() {
        addButton = PaneButton.make(symbol: "plus", label: "Add Project", target: nil, action: nil)
        super.init()
        addButton.target = self
        addButton.action = #selector(requestNewProject)
        topRow.trailingItems.addArrangedSubview(addButton)
        configureTable()
        layOut()
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    /// The view that takes the keyboard focus when the pane gets it.
    public var focusView: NSView { table }

    public var selection: ProjectsListEntry {
        (rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].entry : nil) ?? .allSessions
    }

    /// Shows new content. Only the rows that changed update, and the
    /// selection stays on its entry, or goes to "All Projects" when its
    /// project went away.
    public func show(_ content: ProjectsListContent) {
        let selected = selection
        let newRows = ProjectsListRow.rows(for: content)
        let changes = RowChanges(from: rows, to: newRows) { $0.kind }
        (self.content, rows) = (content, newRows)
        usage.show(content.accounts)
        isShowingChanges = true
        defer { isShowingChanges = false }
        changes.apply(to: table) { index in
            let view = table.view(atColumn: 0, row: index, makeIfNecessary: false)
            (view as? ProjectCellView)?.show(rows[index])
            (view as? ProjectsHeadingCellView)?.show(rows[index])
        }
        if selection != selected {
            select(rows.contains { $0.entry == selected } ? selected : .allSessions)
            if selection != selected { delegate?.projectsList(self, didSelect: selection) }
        }
    }

    /// Selects an entry without a report to the delegate.
    public func select(_ entry: ProjectsListEntry) {
        guard let index = rows.firstIndex(where: { $0.entry == entry }) else { return }
        isShowingChanges = true
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        isShowingChanges = false
        table.scrollRowToVisible(index)
    }

    /// Starts the edit of a project's name in its row.
    public func beginRename(of project: UUID) {
        guard let index = rows.firstIndex(where: { $0.entry == .project(project) }) else { return }
        table.scrollRowToVisible(index)
        guard let cell = table.view(atColumn: 0, row: index, makeIfNecessary: true) as? ProjectCellView else { return }
        cell.name.isEditable = true
        cell.name.delegate = self
        view.window?.makeFirstResponder(cell.name)
    }

    @objc func requestNewProject() {
        delegate?.projectsListDidRequestNewProject(self)
    }

    private func layOut() {
        // The list takes the room that the usage of the accounts leaves. A hidden foot takes none.
        let body = NSStackView(views: [scroll, usage])
        (body.orientation, body.alignment, body.spacing) = (.vertical, .width, 0)
        usage.setContentHuggingPriority(.required, for: .vertical)
        topRow.translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(body)
        view.addSubview(topRow)
        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: view.topAnchor),
            topRow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topRow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            body.topAnchor.constraint(equalTo: topRow.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
