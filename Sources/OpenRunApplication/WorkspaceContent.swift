import AppKit
import MainWindow
import SessionOverview
import SessionPane

/// What the third pane shows: the session of the selected row, a notice,
/// or its empty state.
extension Workspace {
    /// What the third pane must show now.
    var wantedContent: ShownContent {
        let row = layout.selectedRow.flatMap { layout.row($0) }
        if let thread = row?.pane.leadingThread, let summary = connection.overview.thread(thread) {
            // Open in Terminal: the row of the thread shows the terminal of its conversation.
            if let terminal = summary.terminalSession, connection.overview.session(terminal) != nil { return .session(terminal) }
            return .thread(thread)
        }
        guard let session = row?.pane.sessions.first, !exitedSessions.contains(session) else {
            if case .disconnected(let reason) = connection.status { return .notice(.noSessionProcess(reason: reason)) }
            return .nothing
        }
        return lostSessions.contains(session) ? .notice(.lostSession) : .session(session)
    }

    /// Shows the pane of the first session of the selected row, or what
    /// takes its place. The content takes the keyboard focus when the
    /// content before it had the focus, or when the user asked for this
    /// session.
    func showSelectedRow() {
        let wanted = wantedContent
        let asked = sessionToSelect.map { [ShownContent.session($0), .thread($0)].contains(wanted) } ?? false
        let takesFocus = isContentActive || asked
        if takesFocus { sessionToSelect = nil }
        guard wanted != shown || shownIsStale else { return }
        if let shownSession { panes.existing(shownSession)?.deactivate() }
        (shown, shownIsStale) = (wanted, false)
        switch wanted {
        case .nothing:
            window.showContent(nil)
        case .notice(let notice):
            let view = PaneNoticeView(notice)
            view.action = { [weak self] in self?.connectAgain() }
            window.showContent(PaneContent(view: view, title: "", minimumSize: PaneNoticeView.minimumSize))
        case .thread(let thread):
            showChat(of: thread)
        case .session(let session):
            let (pane, isNew) = panes.pane(for: session)
            var content = PaneContent(pane.content)
            if let thread = threadTerminals[session] { content.topRowItems = [backToChatButton(for: thread)] }
            window.showContent(content)
            if isNew {
                configure(pane)
                // The pane estimates its grid from its size, so the window lays it out first.
                window.window.layoutIfNeeded()
                pane.attach()
            }
        }
        if takesFocus { window.focusContent() }
    }

    /// The feed says that a session ended. Its pane closes, and the third
    /// pane takes other content at the next refresh.
    func sessionEnded(_ session: UUID) {
        panes.close(session)
        lostSessions.remove(session)
        exitedSessions.remove(session)
        clearedAlerts[session] = nil
        if shownSession == session { shownIsStale = true }
    }

    /// The user wants a new connection to the session of the selected row.
    func connectAgain() {
        if let session = layout.selectedRow.flatMap({ layout.row($0) })?.pane.sessions.first { lostSessions.remove(session) }
        refresh()
    }

    /// The connection of the app to the session process came or went.
    func statusChanged() {
        // A new connection brings a new list, so each session can try again.
        if connection.status == .connected { lostSessions = [] }
        refresh()
    }
}

/// The map from the value of a session pane to the content of the third pane.
extension PaneContent {
    init(_ session: SessionPaneContent) {
        self.init(view: session.view, title: session.title, minimumSize: session.minimumSize, focusView: session.focusView, textInset: session.textInset)
    }
}
