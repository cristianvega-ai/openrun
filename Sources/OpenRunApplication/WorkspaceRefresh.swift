import AppKit
import ListContent
import MainWindow
import ProjectsList
import SessionOverview
import SessionPane
import SessionsList

/// From the facts of the session process to the lists and the third pane.
extension Workspace {
    /// A batch of changes came from the feed.
    func overviewChanged(from previous: SessionOverview) {
        let overview = connection.overview
        let (shownRows, selectedBefore) = (window.sessionsList.shownIdentifiers, layout.selectedRow)
        // Before the first list, no session is known, and the kept rows stay.
        if connection.hasSessionList { layout.follow(sessions: overview.sessions.map(\.identifier)) }
        if overview.settings != previous.settings { settings = LiveSettings.values(from: overview.settings) }
        for session in previous.sessions where overview.session(session.identifier) == nil {
            panes.close(session.identifier)
            if shownSession == session.identifier { shownSession = nil }
        }
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
        if let project = projectToSelect, content.projects.projects.contains(where: { $0.identifier == project }) {
            window.projectsList.select(.project(project))
            projectToSelect = nil
        }
        // The first pane goes to "All Sessions" when its project went away.
        let entry = window.projectsList.selection
        layout.selectedEntry = entry.layoutEntry
        // The login shell is "New Terminal", and each other command of the settings has an item of its own.
        let commands = settings.newSessionCommands.filter { !$0.commandLine.isEmpty }.map(\.name)
        window.sessionsList.show(SessionsListContent(title: content.title(of: entry), rows: content.rows(of: entry), terminalCommands: commands))
        window.sessionsList.select(layout.selectedRow)
        showSelectedRow()
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

    /// Shows the pane of the first session of the selected row. A pane
    /// that is new attaches after the window laid it out, because it
    /// estimates its grid from its size.
    func showSelectedRow() {
        let session = layout.selectedRow.flatMap { layout.row($0) }?.pane.sessions.first
        let takesFocus = isContentActive || (session != nil && session == sessionToSelect)
        if session == sessionToSelect { sessionToSelect = nil }
        guard session != shownSession else { return }
        if let shownSession { panes.existing(shownSession)?.deactivate() }
        shownSession = session
        guard let session else { return window.showContent(nil) }
        let (pane, isNew) = panes.pane(for: session)
        window.showContent(PaneContent(pane.content))
        if isNew {
            window.window.layoutIfNeeded()
            pane.attach()
        }
        if takesFocus { window.focusContent() }
    }
}

/// The map from the value of a session pane to the content of the third pane.
extension PaneContent {
    init(_ session: SessionPaneContent) {
        self.init(view: session.view, title: session.title, minimumSize: session.minimumSize, focusView: session.focusView, textInset: session.textInset)
    }
}
