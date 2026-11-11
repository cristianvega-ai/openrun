import AppKit

/// The keyboard focus moves between the panes with a command, and the host
/// learns when the content of the third pane becomes active.
extension MainWindowController {
    /// The views that take the focus in turn: each visible list, then the content.
    var focusTargets: [NSView] {
        var targets: [NSView] = []
        if !projectsItem.isCollapsed { targets.append(projectsList.focusView) }
        if !sessionsItem.isCollapsed { targets.append(sessionsList.focusView) }
        if let content = contentPane.content { targets.append(content.focusView) }
        return targets
    }

    @objc public func focusNextPane(_ sender: Any?) {
        moveFocus(by: 1)
    }

    @objc public func focusPreviousPane(_ sender: Any?) {
        moveFocus(by: -1)
    }

    /// Moves the focus to the content, such as after Return in the sessions list.
    public func focusContent() {
        if let content = contentPane.content { paneWindow.makeFirstResponder(content.focusView) }
    }

    private func moveFocus(by step: Int) {
        let targets = focusTargets
        guard !targets.isEmpty else { return }
        let responder = paneWindow.firstResponder as? NSView
        let current = targets.firstIndex { responder?.isDescendant(of: $0) == true }
        let next = current.map { ($0 + step + targets.count) % targets.count } ?? (step > 0 ? 0 : targets.count - 1)
        paneWindow.makeFirstResponder(targets[next])
    }

    /// The content is active while the window is key and the focus is in the content.
    func updateContentActivity() {
        let responder = paneWindow.firstResponder as? NSView
        let isActive = isWindowKey() && responder?.isDescendant(of: contentPane.contentArea) == true
        guard isActive != isContentActive else { return }
        isContentActive = isActive
        if isActive { delegate?.mainWindowContentDidBecomeActive(self) } else { delegate?.mainWindowContentDidResignActive(self) }
    }

    public func windowDidBecomeKey(_ notification: Notification) {
        updateContentActivity()
    }

    public func windowDidResignKey(_ notification: Notification) {
        updateContentActivity()
    }

    public func windowWillClose(_ notification: Notification) {
        delegate?.mainWindowWillClose(self)
    }
}
