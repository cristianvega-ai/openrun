import AppKit
import MainWindow
import SessionPane

/// What the panes and the window tell the host.
extension Workspace: SessionPaneDelegate, MainWindowDelegate {
    /// Gives a new pane its host and the settings of the user.
    func configure(_ pane: SessionPaneController) {
        pane.delegate = self
        pane.asksBeforeUnsafePaste = settings.asksBeforeUnsafePaste
        pane.configureTerminalView = { [weak self] view in
            if let self { LiveSettings.apply(self.settings, to: view) }
        }
    }

    /// The settings changed. Each pane takes them at once, also a pane
    /// that the window does not show now.
    func settingsChanged() {
        settings = LiveSettings.values(from: connection.overview.settings)
        settingsWindow?.show(settingTexts)
        // A chat offers the accounts of the settings to a thread at its limit.
        updateThreadPanes()
        for pane in panes.all {
            pane.asksBeforeUnsafePaste = settings.asksBeforeUnsafePaste
            if let view = pane.terminalView { LiveSettings.apply(settings, to: view) }
        }
    }

    /// The title of the third pane is the title of its row, which the
    /// feed brings with the facts of the session.
    func sessionPane(_ pane: SessionPaneController, didChangeTitle title: String) {}

    func sessionPaneDidChangeMinimumSize(_ pane: SessionPaneController) {
        if panes.session(of: pane) == shownSession { window.updateContentMinimumSize(pane.minimumSize) }
    }

    /// The program ended, or the connection failed and the user saw why.
    func sessionPaneDidEnd(_ pane: SessionPaneController) {
        guard let session = panes.session(of: pane) else { return }
        // The feed removes the row of a program that ended. Until then the
        // row must not attach again. A session that lost only its
        // connection keeps its row and gets a notice.
        if pane.hasConnectionFailure { lostSessions.insert(session) } else { exitedSessions.insert(session) }
        panes.close(session)
        if shownSession == session { shownIsStale = true }
        refresh()
    }

    /// The connection of a pane failed while the window did not show it.
    /// The pane closes, and the next selection of its row attaches again.
    func sessionPane(_ pane: SessionPaneController, didFailWithMessage message: String) {
        if let session = panes.session(of: pane) { panes.close(session) }
    }

    func mainWindowContentDidBecomeActive(_ window: MainWindowController) {
        isContentActive = true
        if let shownSession {
            panes.existing(shownSession)?.activate()
            clearAlert(of: shownSession)
        }
        // The session in view shows no mark. The window also reports
        // this while a refresh changes the content, and that refresh goes on.
        if !isRefreshing { refresh() }
    }

    func mainWindowContentDidResignActive(_ window: MainWindowController) {
        isContentActive = false
        if let shownSession { panes.existing(shownSession)?.deactivate() }
        if !isRefreshing { refresh() }
    }

    /// The sessions go on. The panes detach, so no pane reads output for
    /// a window that is closed. The feed stays, for the alerts.
    func mainWindowWillClose(_ window: MainWindowController) {
        panes.closeAll()
        threadPanes.closeAll()
        (shown, shownIsStale, isContentActive) = (.nothing, false, false)
        window.showContent(nil)
    }
}
