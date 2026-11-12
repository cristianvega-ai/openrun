import AppKit

/// The menu commands of the main window. Each item is on only when it can act.
extension Workspace: NSMenuItemValidation, NSMenuDelegate {
    @objc func newSession(_ sender: Any?) {
        newSession()
    }

    /// File > New Thread: a thread with the first agent, under the
    /// account that the user chose last for it.
    @objc func newThread(_ sender: Any?) {
        newThread(agent: Self.threadAgents[0], account: lastAccount(of: Self.threadAgents[0]))
    }

    /// The item holds the shown name of a new-session command of the settings.
    @objc func newSessionWithCommand(_ sender: NSMenuItem) {
        newSession(commandNamed: sender.representedObject as? String)
    }

    /// What Command-W closes now, for the title of its menu item.
    enum CloseTarget { case thread, terminal, webPage }

    static func closeTitle(of target: CloseTarget?) -> String {
        switch target {
        case .thread: "Close Thread"
        case .webPage: "Close Web Page"
        case .terminal, nil: "Close Terminal"
        }
    }

    /// The kind of the pane with the focus, or of the first pane of the selected row.
    var closeTarget: CloseTarget? {
        guard let leaf = focusedLeaf ?? layout.selectedRow.flatMap({ layout.row($0) })?.pane.leaves.first else { return nil }
        if layout.browser(leaf) != nil { return .webPage }
        return connection.overview.thread(leaf) != nil || threadTerminals[leaf] != nil ? .thread : .terminal
    }

    /// Command-W: closes the selected row, or the pane with the focus
    /// when the row has splits.
    @objc func closeSession(_ sender: Any?) {
        if case .split = shown, let leaf = focusedLeaf { return closeLeaf(leaf) }
        if let row = layout.selectedRow { closeRow(row) }
    }

    @objc func renameSession(_ sender: Any?) {
        if let row = window.sessionsList.selection { window.sessionsList.beginRename(of: row) }
    }

    /// Command-K: clears the scrollback of the session that the third pane shows.
    @objc func clearSession(_ sender: Any?) {
        shownSession.flatMap { panes.existing($0) }?.clearScrollback()
    }

    @objc func selectNextSession(_ sender: Any?) {
        moveSelection(by: 1)
    }

    @objc func selectPreviousSession(_ sender: Any?) {
        moveSelection(by: -1)
    }

    @objc func showMainWindow(_ sender: Any?) {
        showWindow()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(closeSession(_:)) { item.title = Self.closeTitle(of: closeTarget) }
        return switch item.action {
        case #selector(newSession(_:)), #selector(newSessionWithCommand(_:)): connection.status == .connected
        case #selector(newThread(_:)): connection.status == .connected && connection.hasThreadList
        // The window shows the values of the session process, so it needs them first.
        case #selector(showSettings(_:)): !connection.overview.settings.isEmpty
        case #selector(installCommandLineTool(_:)): toolInstallation != nil
        case #selector(closeSession(_:)): window.window.isVisible && layout.selectedRow != nil
        case #selector(renameSession(_:)): window.window.isVisible && window.sessionsList.selection != nil
        case #selector(clearSession(_:)): window.window.isVisible && shownSession != nil
        case #selector(splitRight(_:)), #selector(splitDown(_:)): connection.status == .connected && window.window.isVisible && focusedLeaf != nil
        case #selector(splitWithBrowser(_:)): window.window.isVisible && focusedLeaf != nil
        case #selector(openFocusedThreadInTerminal(_:)): connection.status == .connected && window.window.isVisible && focusedThread?.isInTerminal == false
        case #selector(returnFocusedThreadToChat(_:)): connection.status == .connected && window.window.isVisible && focusedThread?.isInTerminal == true
        // A session process of an older build does not know the request.
        case #selector(restartSessionProcess(_:)): connection.status == .connected && connection.sessionProcessBuild != nil
        case #selector(selectNextPane(_:)), #selector(selectPreviousPane(_:)): if case .split = shown { window.window.isVisible } else { false }
        case #selector(selectNextSession(_:)), #selector(selectPreviousSession(_:)): !window.sessionsList.shownIdentifiers.isEmpty
        default: true
        }
    }

    /// Fills the menu "New Session With" from the settings, when it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for command in settings.newSessionCommands where !command.commandLine.isEmpty {
            let item = menu.addItem(withTitle: command.name, action: #selector(newSessionWithCommand(_:)), keyEquivalent: "")
            (item.target, item.representedObject) = (self, command.name)
        }
    }
}
