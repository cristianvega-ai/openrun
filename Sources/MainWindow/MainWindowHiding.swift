import AppKit
import PaneAppearance

/// The menu commands that hide and show the two lists, with a smooth
/// animation unless the user asks for less motion.
extension MainWindowController: NSMenuItemValidation {
    @objc public func toggleProjectsList(_ sender: Any?) {
        setCollapsed(!projectsItem.isCollapsed, projectsItem)
    }

    @objc public func toggleSessionsList(_ sender: Any?) {
        setCollapsed(!sessionsItem.isCollapsed, sessionsItem)
    }

    /// The items for the View menu of the host, with their key equivalents.
    /// Control-Tab moves the focus between the panes, as between tabs.
    public func paneMenuItems() -> [NSMenuItem] {
        let projects = NSMenuItem(title: "Hide Projects", action: #selector(toggleProjectsList), keyEquivalent: "1")
        let sessions = NSMenuItem(title: "Hide Sessions", action: #selector(toggleSessionsList), keyEquivalent: "2")
        for item in [projects, sessions] {
            (item.target, item.keyEquivalentModifierMask) = (self, [.command, .control])
        }
        let next = NSMenuItem(title: "Move Focus to Next Pane", action: #selector(focusNextPane), keyEquivalent: "\t")
        let previous = NSMenuItem(title: "Move Focus to Previous Pane", action: #selector(focusPreviousPane), keyEquivalent: "\t")
        (next.target, next.keyEquivalentModifierMask) = (self, [.control])
        (previous.target, previous.keyEquivalentModifierMask) = (self, [.control, .shift])
        return [projects, sessions, next, previous]
    }

    /// The title of each item says what it does now.
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleProjectsList): menuItem.title = projectsItem.isCollapsed ? "Show Projects" : "Hide Projects"
        case #selector(toggleSessionsList): menuItem.title = sessionsItem.isCollapsed ? "Show Sessions" : "Hide Sessions"
        default: break
        }
        return true
    }

    func setCollapsed(_ collapsed: Bool, _ item: NSSplitViewItem) {
        let animates = !reducesMotion()
        if animates, animationGeneration == finishedAnimationGeneration { contentPane.beginPaneResize() }
        // The window takes the minimum of the final layout before the panes
        // move. So the animation never asks for a size that the minimum refuses.
        if item === projectsItem { layout.projectsHidden = collapsed } else { layout.sessionsHidden = collapsed }
        updateTopRowSpaces()
        updateChosenWidths()
        keepMinimumSize()
        if !animates {
            item.isCollapsed = collapsed
            layout.save(to: defaults)
        } else {
            animationGeneration += 1
            let generation = animationGeneration
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                item.animator().isCollapsed = collapsed
            }, completionHandler: { [weak self] in MainActor.assumeIsolated { self?.animationEnded(generation) } })
            // AppKit did not always call the completion of two animations
            // that overlap, so the end also comes after a time limit.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.animationEnded(generation)
            }
        }
    }

    /// Only the end of the last animation ends the hold of the content
    /// width, so overlapping animations give one size at the end.
    func animationEnded(_ generation: Int) {
        guard generation == animationGeneration, finishedAnimationGeneration != generation else { return }
        finishedAnimationGeneration = generation
        paneResizeEnded()
    }

    /// The button of the lists goes to the first row of the final layout. A
    /// constraint to the window, not a fixed inset, keeps the controls clear of
    /// the traffic lights, so they move with their pane in an animation.
    func updateTopRowSpaces() {
        let rows = [layout.projectsHidden ? nil : projectsList.topRow, layout.sessionsHidden ? nil : sessionsList.topRow, contentPane.topRow]
        let first = rows.compactMap { $0 }[0]
        if lightsClearances.isEmpty, let root = paneWindow.contentView {
            lightsClearances = [projectsList.topRow, sessionsList.topRow, contentPane.topRow].map { row in
                let clearance = row.leadingItems.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor)
                // A pane that slides away can be too narrow for the clearance.
                // Below the hold of every pane, the clearance never holds a pane open.
                clearance.priority = .init(240)
                clearance.isActive = true
                return clearance
            }
        }
        lightsClearances.forEach { $0.constant = isInFullScreen ? 0 : paneWindow.trafficLightsSpace }
        for row in [projectsList.topRow, sessionsList.topRow] { row.leadingSpace = 16 }
        contentPane.topRow.leadingSpace = contentPane.content?.textInset ?? 16
        listsButton.removeFromSuperview()
        first.leadingItems.insertArrangedSubview(listsButton, at: 0)
        let label = layout.projectsHidden ? "Show Projects" : "Hide Projects"
        listsButton.toolTip = label
        listsButton.setAccessibilityLabel(label)
    }
}
