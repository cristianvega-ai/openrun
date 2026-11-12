import AppKit
import BrowserPane
import MainWindow
import PaneSplits
import SessionConnection
import SessionProtocol
import TerminalView
import WindowLayout

/// The splits of the third pane (decision of 2026-11-10): a row shows
/// its sessions and threads side by side or one over the other.
extension Workspace {
    /// The pane of a row without the sessions that ended and the threads that closed.
    func living(_ pane: LayoutPane) -> LayoutPane? {
        let overview = connection.overview
        return pane.keeping { (overview.session($0) != nil && !exitedSessions.contains($0)) || overview.thread($0) != nil }
    }

    /// The session or the thread in the third pane that has the keyboard
    /// focus. In a row with splits it is the leaf of the focused view, or
    /// the leaf that had the focus last.
    var focusedLeaf: UUID? {
        switch shown {
        case .session(let session): return session
        case .thread(let thread): return thread
        case .split(_, let pane):
            let focused = splitView?.leaf(holding: window.window.firstResponder as? NSView)
            return focused ?? lastFocusedLeaf.flatMap { pane.leaves.contains($0) ? $0 : nil } ?? pane.leaves.first
        case .nothing, .notice: return nil
        }
    }

    /// Shows a row with splits. A new session pane attaches after the
    /// window laid it out, because it estimates its grid from its size.
    func showSplit(row: UUID, pane: LayoutPane, focus: UUID?) {
        var new: [UUID] = []
        var minimumSizes: [UUID: CGSize] = [:], focusViews: [UUID: NSView] = [:]
        let view = SplitPaneView(pane: pane) { leaf in
            if let browser = layout.browser(leaf) {
                let page = browserPane(of: browser)
                (minimumSizes[leaf], focusViews[leaf]) = (BrowserPaneController.minimumSize, page.focusView)
                return page.view
            }
            let thread = connection.overview.thread(leaf)
            // Open in Terminal: the terminal of the conversation takes the place of the chat.
            let terminal = thread?.terminalSession.flatMap { connection.overview.session($0)?.identifier }
            if let thread, terminal == nil {
                let chat = chatPane(of: thread).chat
                let view = chat.view
                // The message field takes the keyboard. The view around it cannot.
                (minimumSizes[leaf], focusViews[leaf]) = (chat.minimumSize, chat.focusView)
                return view
            }
            let (session, isNew) = panes.pane(for: terminal ?? leaf)
            if isNew { new.append(terminal ?? leaf) }
            (minimumSizes[leaf], focusViews[leaf]) = (session.minimumSize, session.content.focusView)
            return session.content.view
        }
        view.fractionChanged = { [weak self] leaf, fraction in self?.keepFraction(fraction, ofSplitBefore: leaf, inRow: row) }
        splitView = view
        let leaf = focus.flatMap { pane.leaves.contains($0) ? $0 : nil } ?? pane.leaves.first
        lastFocusedLeaf = leaf
        let minimum = SplitPaneView.minimumSize(of: pane) { minimumSizes[$0] ?? .zero }
        window.showContent(PaneContent(view: view, title: "", minimumSize: minimum, focusView: leaf.flatMap { focusViews[$0] }))
        for session in new { panes.existing(session).map { configure($0, of: session) } }
        window.window.layoutIfNeeded()
        for session in new { panes.existing(session)?.attach() }
    }

    /// The user moved a divider. The layout keeps the new share.
    func keepFraction(_ fraction: Double, ofSplitBefore leaf: UUID, inRow row: UUID) {
        layout.setFraction(fraction, ofSplitBefore: leaf, inRow: row)
        // The view has the share already, so the pane needs no new view.
        if case .split(let shownRow, _) = shown, shownRow == row, let pane = layout.row(row).flatMap({ living($0.pane) }) {
            shown = .split(row: row, pane: pane)
        }
        layoutStore.save(layout)
    }

    @objc func splitRight(_ sender: Any?) { split(.sideBySide) }
    @objc func splitDown(_ sender: Any?) { split(.stacked) }

    /// Starts a login shell beside or under the pane with the focus, in
    /// the current folder of that pane (decision of 2026-11-10).
    func split(_ direction: LayoutSplit.Direction) {
        guard let leaf = focusedLeaf else { return }
        let overview = connection.overview
        let folder = overview.session(leaf).map { $0.currentFolder ?? $0.folder } ?? overview.thread(leaf)?.folder ?? home
        // The new pane gets half of the room of the third pane.
        var area = window.contentAreaSize
        if direction == .sideBySide { area.width /= 2 } else { area.height /= 2 }
        let grid = TerminalView.estimatedGrid(for: area, scale: window.window.backingScaleFactor)
        let request = NewSessionLaunch(commandLine: "", folder: folder, shell: loginShell)
            .request(size: SessionSize(columns: grid.columns, rows: grid.rows), environment: sessionEnvironment)
        requests.perform({ client in
            guard case .sessionCreated(let summary) = try client.request(request) else { throw SessionConnectionError.unexpectedAnswer(request: "new session") }
            return summary.identifier
        }, then: { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let session):
                // The feed can bring the session first, with a row of its own. The split takes that row away.
                if layout.split(leaf, with: session, direction: direction) { (leafToFocus, lastFocusedLeaf) = (session, session) }
                layoutStore.save(layout)
                refresh()
            case .failure(let failure): showFailure("The split could not start", failure.message)
            }
        })
    }

    /// Moves the keyboard focus to the next or the previous pane of the row, around the end.
    func focusPane(by step: Int) {
        guard case .split(_, let pane) = shown, let leaf = focusedLeaf, let index = pane.leaves.firstIndex(of: leaf) else { return }
        let next = pane.leaves[(index + step + pane.leaves.count) % pane.leaves.count]
        lastFocusedLeaf = next
        if let view = focusView(of: next) { window.window.makeFirstResponder(view) }
    }

    /// The view of a pane of the shown row that takes the keyboard: the
    /// web page, the terminal of a conversation, the message field of a
    /// chat, or the terminal of a session.
    func focusView(of leaf: UUID) -> NSView? {
        if let page = browserPanes[leaf] { return page.focusView }
        guard let thread = connection.overview.thread(leaf) else { return panes.existing(leaf)?.content.focusView }
        if let terminal = thread.terminalSession, let pane = panes.existing(terminal) { return pane.content.focusView }
        return threadPanes.existing(leaf)?.chat.focusView
    }

    @objc func selectNextPane(_ sender: Any?) { focusPane(by: 1) }
    @objc func selectPreviousPane(_ sender: Any?) { focusPane(by: -1) }

    /// Closes one session or one thread of a row, as Command-W does for
    /// the pane with the focus. The session asks first when a program
    /// other than a shell at its prompt runs in it.
    func closeLeaf(_ leaf: UUID) {
        if layout.browser(leaf) != nil { return closeBrowser(leaf) }
        if connection.overview.thread(leaf) != nil { return closeThread(leaf) }
        guard let session = connection.overview.session(leaf) else { return }
        let end = { [weak self] in
            self?.perform("The session could not close") { _ = try $0.request(.killSession(identifier: leaf)) } ?? ()
        }
        guard let question = CloseQuestion(session: session) else { return end() }
        confirmClose(question) { agreed in
            if agreed { end() }
        }
    }
}
