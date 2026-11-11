import AppKit
import ListContent
import ProjectsList
import SessionOverview
import SessionsList

/// From the facts of the session process to the lists and the third pane.
extension Workspace {
    /// A batch of changes came from the feed.
    func overviewChanged(from previous: SessionOverview) {
        let overview = connection.overview
        let (shownRows, selectedBefore) = (window.sessionsList.shownIdentifiers, layout.selectedRow)
        // Before the first list, no session is known, and the kept rows stay.
        if connection.hasSessionList { layout.follow(sessions: overview.sessions.map(\.identifier)) }
        if let wanted = sessionToSelect, let row = layout.row(showing: wanted) {
            layout.selectedRow = row.identifier
        } else if layout.selectedRow == nil, let selectedBefore {
            // The selected session ended. The row that took its place gets the selection.
            layout.selectedRow = RowNeighbor.of(selectedBefore, in: shownRows, remaining: Set(layout.rows.map(\.identifier)))
        }
        refresh()
    }

    /// Gives the two lists their content, and the third pane the selected row.
    func refresh() {
        isRefreshing = true
        defer { isRefreshing = false }
        let content = ListContent(overview: connection.overview, layout: layout, inView: sessionInView, home: home)
        window.projectsList.show(content.projects)
        // The first pane goes to "All Sessions" when its project went away.
        let entry = window.projectsList.selection
        layout.selectedEntry = entry.layoutEntry
        window.sessionsList.show(SessionsListContent(title: content.title(of: entry), rows: content.rows(of: entry)))
        window.sessionsList.select(layout.selectedRow)
        if layout != savedLayout {
            savedLayout = layout
            layoutStore.save(layout)
        }
    }

    /// The session that the user looks at and types into: the one in the
    /// third pane, while the window is key and the focus is in that pane.
    var sessionInView: UUID? {
        isContentActive ? shownSession : nil
    }
}
