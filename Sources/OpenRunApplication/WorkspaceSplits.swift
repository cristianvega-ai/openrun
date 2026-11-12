import AppKit
import MainWindow
import PaneSplits
import WindowLayout

/// The splits of the third pane (decision of 2026-11-10): a row shows
/// its sessions and threads side by side or one over the other.
extension Workspace {
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
            if let thread = connection.overview.thread(leaf) {
                let chat = chatPane(of: thread).chat
                (minimumSizes[leaf], focusViews[leaf]) = (chat.minimumSize, chat.view)
                return chat.view
            }
            let (session, isNew) = panes.pane(for: leaf)
            if isNew { new.append(leaf) }
            (minimumSizes[leaf], focusViews[leaf]) = (session.minimumSize, session.content.focusView)
            return session.content.view
        }
        splitView = view
        let leaf = focus.flatMap { pane.leaves.contains($0) ? $0 : nil } ?? pane.leaves.first
        lastFocusedLeaf = leaf
        let minimum = SplitPaneView.minimumSize(of: pane) { minimumSizes[$0] ?? .zero }
        window.showContent(PaneContent(view: view, title: "", minimumSize: minimum, focusView: leaf.flatMap { focusViews[$0] }))
        for session in new { panes.existing(session).map(configure) }
        window.window.layoutIfNeeded()
        for session in new { panes.existing(session)?.attach() }
    }
}
