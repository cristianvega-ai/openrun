import AppKit
import PaneAppearance

/// The three panes in their split view, their widths, and the shadows between them.
extension MainWindowController {
    func configurePanes() {
        let splitView = PaneSplitView()
        splitView.dragStarted = { [weak self] in self?.dragStarted() }
        splitView.dragEnded = { [weak self] in self?.dragEnded() }
        splitController.splitView = splitView
        splitController.splitView.isVertical = true
        splitController.splitView.dividerStyle = .thin
        (projectsItem.minimumThickness, projectsItem.maximumThickness) = (PaneLayout.projectsWidths.lowerBound, PaneLayout.projectsWidths.upperBound)
        (sessionsItem.minimumThickness, sessionsItem.maximumThickness) = (PaneLayout.sessionsWidths.lowerBound, PaneLayout.sessionsWidths.upperBound)
        // The first pane holds its width the hardest, so a drag of the second
        // edge changes only the second pane, and a resize of the window changes the third.
        (projectsItem.holdingPriority, sessionsItem.holdingPriority, contentItem.holdingPriority) = (.init(270), .init(260), .init(250))
        // A list hides only through its button, its menu command and its key
        // (decision of 2026-11-10). A drag of an edge stops at the minimum width.
        (projectsItem.canCollapse, sessionsItem.canCollapse) = (false, false)
        // A show takes the room of the list from the content, and a hide gives
        // it back, so the window keeps its width. The window grows first when
        // the content cannot spare the room. AppKit otherwise added the width
        // of the list to the window again, past the minimum and the screen.
        for item in [projectsItem, sessionsItem] { item.collapseBehavior = .useConstraints }
        [projectsItem, sessionsItem, contentItem].forEach(splitController.addSplitViewItem)
        let root = NSView()
        paneWindow.contentView = root
        splitController.view.frame = root.bounds
        splitController.view.autoresizingMask = [.width, .height]
        root.addSubview(splitController.view)
        root.addSubview(contentShadow)
        root.addSubview(sessionsShadow)
        paneWindow.layoutIfNeeded()
        let divider = splitController.splitView.dividerThickness
        splitController.splitView.setPosition(layout.projectsWidth, ofDividerAt: 0)
        splitController.splitView.setPosition(layout.projectsWidth + divider + layout.sessionsWidth, ofDividerAt: 1)
        // A position applies to a visible pane, so the panes hide after their widths apply.
        (projectsItem.isCollapsed, sessionsItem.isCollapsed) = (layout.projectsHidden, layout.sessionsHidden)
        // The split view controller is the delegate of its split view, so the window listens for the resize.
        NotificationCenter.default.addObserver(self, selector: #selector(panesDidResize),
            name: NSSplitView.didResizeSubviewsNotification, object: splitController.splitView)
        placeShadows()
        updateTopRowSpaces()
    }

    /// Moves the shadows with the panes. Only the end of a drag changes the
    /// chosen widths, so a squeeze does not.
    @objc func panesDidResize(_ notification: Notification) {
        placeShadows()
    }

    /// An animation or a drag of the panes ends. The layout is saved once
    /// here, not at each step of the change.
    func paneResizeEnded() {
        contentPane.endPaneResize()
        layout.save(to: defaults)
    }

    /// Each visible pane after the first casts a shadow on the pane at its left.
    func placeShadows() {
        let height = splitController.view.bounds.height
        let sessionsEdge = frame(of: sessionsList.view).minX, contentEdge = frame(of: contentPane.view).minX
        sessionsShadow.frame = NSRect(x: sessionsEdge - SheetShadowView.width, y: 0, width: SheetShadowView.width, height: height)
        contentShadow.frame = NSRect(x: contentEdge - SheetShadowView.width, y: 0, width: SheetShadowView.width, height: height)
        sessionsShadow.isHidden = sessionsItem.isCollapsed || projectsItem.isCollapsed
        contentShadow.isHidden = contentEdge <= 0
    }

    /// The frame of a pane in the content view of the window. The split view
    /// controller holds each pane in a view of its own.
    func frame(of pane: NSView) -> NSRect {
        pane.convert(pane.bounds, to: paneWindow.contentView)
    }
}
