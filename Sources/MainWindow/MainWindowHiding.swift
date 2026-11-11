import AppKit

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
    public func paneMenuItems() -> [NSMenuItem] {
        let projects = NSMenuItem(title: "Hide Projects", action: #selector(toggleProjectsList), keyEquivalent: "1")
        let sessions = NSMenuItem(title: "Hide Sessions", action: #selector(toggleSessionsList), keyEquivalent: "2")
        for item in [projects, sessions] {
            (item.target, item.keyEquivalentModifierMask) = (self, [.command, .control])
        }
        return [projects, sessions]
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
        if reducesMotion() {
            item.isCollapsed = collapsed
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.allowsImplicitAnimation = true
                item.animator().isCollapsed = collapsed
            }
        }
        (layout.projectsHidden, layout.sessionsHidden) = (projectsItem.isCollapsed, sessionsItem.isCollapsed)
        layout.save(to: defaults)
        updateTopRowSpaces()
        keepMinimumSize()
    }

    /// The traffic lights sit in the top row of the first visible pane, so
    /// that row keeps room for them.
    func updateTopRowSpaces() {
        let lights = paneWindow.trafficLightsSpace
        projectsList.topRow.leadingSpace = lights
        sessionsList.topRow.leadingSpace = projectsItem.isCollapsed ? lights : 16
        contentPane.topRow.leadingSpace = projectsItem.isCollapsed && sessionsItem.isCollapsed ? lights : 16
    }
}
