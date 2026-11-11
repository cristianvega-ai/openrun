import AppKit
import ListUpdates
import PaneAppearance

/// The first pane: "All Sessions", "Needs You", the projects in the user's
/// order, and "No Project". It shows display values and reports what the user does
/// through its delegate.
@MainActor
public final class ProjectsListController: NSObject {
    /// The pane: its top row over the list, on the color of the first pane.
    public let view = PaneBackgroundView(color: PaneColor.firstPane)
    /// The host makes room in the top row for the traffic lights.
    public let topRow = PaneTopRow(background: PaneColor.firstPane)
    public weak var delegate: ProjectsListDelegate?
    public internal(set) var content = ProjectsListContent()
    let table = ProjectsTableView()
    let scroll = NSScrollView()
    var rows = ProjectsListRow.rows(for: ProjectsListContent())
    /// The table selects a row while it shows a change, and that is no choice of the user.
    var isShowingChanges = false

    public override init() {
        super.init()
        configureTable()
        layOut()
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }

    /// The view that takes the keyboard focus when the pane gets it.
    public var focusView: NSView { table }

    public var selection: ProjectsListEntry {
        rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].entry : .allSessions
    }

    private func layOut() {
        topRow.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        view.addSubview(topRow)
        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: view.topAnchor),
            topRow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topRow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topRow.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
