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
    let table = SessionsTableView()
    let scroll = NSScrollView()
    var rows: [SessionsListRow] = []
    /// The table changes its selection while it shows a change, and that is no choice of the user.
    var isShowingChanges = false

    public override init() {
        super.init()
        configureTable()
        layOut()
    }

    /// The view that takes the keyboard focus when the pane gets it.
    public var focusView: NSView { table }

    /// The selected row, if the list shows it.
    public var selection: UUID? {
        rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].identifier : nil
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
