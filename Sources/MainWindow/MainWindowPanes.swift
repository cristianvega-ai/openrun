import AppKit
import PaneAppearance

/// The three panes in their split view, their widths, and the shadows between them.
extension MainWindowController {
    func configurePanes() {
        splitController.splitView = PaneSplitView()
        splitController.splitView.isVertical = true
        splitController.splitView.dividerStyle = .thin
        (projectsItem.minimumThickness, projectsItem.maximumThickness) = (PaneLayout.projectsWidths.lowerBound, PaneLayout.projectsWidths.upperBound)
        (sessionsItem.minimumThickness, sessionsItem.maximumThickness) = (PaneLayout.sessionsWidths.lowerBound, PaneLayout.sessionsWidths.upperBound)
        // The first pane holds its width the hardest, so a drag of the second
        // edge changes only the second pane, and a resize of the window changes the third.
        (projectsItem.holdingPriority, sessionsItem.holdingPriority, contentItem.holdingPriority) = (.init(270), .init(260), .init(250))
        (projectsItem.canCollapse, sessionsItem.canCollapse) = (true, true)
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

    /// Keeps the widths that the user drags, and moves the shadows with the panes.
    @objc func panesDidResize(_ notification: Notification) {
        placeShadows()
        if !projectsItem.isCollapsed { layout.projectsWidth = projectsList.view.frame.width }
        if !sessionsItem.isCollapsed { layout.sessionsWidth = sessionsList.view.frame.width }
        (layout.projectsHidden, layout.sessionsHidden) = (projectsItem.isCollapsed, sessionsItem.isCollapsed)
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
