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
        if connection.hasSessionList {
            // Before the first list of the threads, the rows of the threads stay.
            let terminals = threadTerminals
            layout.follow(
                sessions: overview.sessions.map(\.identifier).filter { terminals[$0] == nil },
                threads: connection.hasThreadList ? overview.threads.map(\.identifier) : nil)
        }
        threadsChanged(from: previous)
        if overview.settings != previous.settings { settingsChanged() }
        alertsChanged(from: previous)
        let isFirstList = showsSessionAtStart && connection.hasFirstLists
        if isFirstList {
            showsSessionAtStart = false
            // A window with a thread is not empty, and it needs no new shell.
            if overview.sessions.isEmpty, overview.threads.isEmpty { newSession() }
        }
        for session in previous.sessions where overview.session(session.identifier) == nil { sessionEnded(session.identifier) }
        if let wanted = sessionToSelect, let row = layout.row(showing: wanted) {
            layout.selectedRow = row.identifier
        } else if layout.selectedRow == nil, let selectedBefore {
            // The selected session ended. The row that took its place gets the selection.
            layout.selectedRow = RowNeighbor.of(selectedBefore, in: shownRows, remaining: Set(layout.rows.map(\.identifier)))
        }
        refresh()
        // The first row is the first one that the list shows, after its filter and its order.
        if isFirstList, layout.selectedRow == nil, let first = window.sessionsList.shownIdentifiers.first {
            layout.selectedRow = first
            refresh()
        }
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
        // A thread is a chat with one of the agents. An older session process keeps no threads.
        let agents = connection.hasThreadList ? Self.threadAgents.map(ThreadRowFacts.agentName) : []
        let accounts = [ThreadRowFacts.agentName("claude-code"): settings.claudeCodeAccounts.map(\.name), ThreadRowFacts.agentName("codex"): settings.codexAccounts.map(\.name)]
        window.sessionsList.show(SessionsListContent(
            title: content.title(of: entry), rows: content.rows(of: entry), agents: agents, accounts: accounts, terminalCommands: commands))
        window.sessionsList.select(layout.selectedRow)
        showSelectedRow()
        // The third pane has the title of its row, so the user reads one
        // name for a session in both places.
        if focusedLeaf != nil, let row = content.rows(of: .allSessions).first(where: { $0.identifier == layout.selectedRow }) {
            window.updateContentTitle(row.title)
        }
        updateBadge(content.projects.needsYouCount)
        if layout != savedLayout {
            savedLayout = layout
            layoutStore.save(layout)
        }
    }

    /// The session or the thread that the user looks at and types into:
    /// the one in the third pane, while the window is key and the focus
    /// is in that pane.
    var sessionInView: UUID? {
        isContentActive ? focusedLeaf : nil
    }

    /// The thread whose chat the third pane shows.
    var shownThread: UUID? {
        if case .thread(let thread) = shown { return thread }
        if case .split = shown, let leaf = focusedLeaf, connection.overview.thread(leaf) != nil { return leaf }
        return nil
    }

    /// The session whose pane the third pane shows.
    var shownSession: UUID? {
        if case .session(let session) = shown { return session }
        if case .split = shown, let leaf = focusedLeaf, connection.overview.session(leaf) != nil { return leaf }
        return nil
    }
}
