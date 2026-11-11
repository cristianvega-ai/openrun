import AppKit
import PaneAppearance

/// The three panes in their split view, and their widths.
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
        projectsItem.isCollapsed = layout.projectsHidden
        sessionsItem.isCollapsed = layout.sessionsHidden
        let root = NSView()
        paneWindow.contentView = root
        splitController.view.frame = root.bounds
        splitController.view.autoresizingMask = [.width, .height]
        root.addSubview(splitController.view)
        // The positions apply only to a split view that has its size.
        paneWindow.layoutIfNeeded()
        let divider = splitController.splitView.dividerThickness
        splitController.splitView.setPosition(layout.projectsWidth, ofDividerAt: 0)
        splitController.splitView.setPosition(layout.projectsWidth + divider + layout.sessionsWidth, ofDividerAt: 1)
        // The split view controller is the delegate of its split view, so the window listens for the resize.
        NotificationCenter.default.addObserver(self, selector: #selector(panesDidResize),
            name: NSSplitView.didResizeSubviewsNotification, object: splitController.splitView)
    }

    /// Keeps the widths that the user drags.
    @objc func panesDidResize(_ notification: Notification) {
        if !projectsItem.isCollapsed { layout.projectsWidth = projectsList.view.frame.width }
        if !sessionsItem.isCollapsed { layout.sessionsWidth = sessionsList.view.frame.width }
        (layout.projectsHidden, layout.sessionsHidden) = (projectsItem.isCollapsed, sessionsItem.isCollapsed)
        layout.save(to: defaults)
    }
}
