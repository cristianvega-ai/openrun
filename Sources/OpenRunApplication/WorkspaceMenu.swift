import AppKit

/// The menu commands of the main window. Each item is on only when it can act.
extension Workspace: NSMenuItemValidation, NSMenuDelegate {
    @objc func newSession(_ sender: Any?) {
        newSession()
    }

    @objc func newThread(_ sender: Any?) {
        newThread()
    }

    /// The item holds the shown name of a new-session command of the settings.
    @objc func newSessionWithCommand(_ sender: NSMenuItem) {
        newSession(commandNamed: sender.representedObject as? String)
    }

    @objc func closeSession(_ sender: Any?) {
        if let row = layout.selectedRow { closeRow(row) }
    }

    @objc func renameSession(_ sender: Any?) {
        if let row = window.sessionsList.selection { window.sessionsList.beginRename(of: row) }
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
        switch item.action {
        case #selector(newSession(_:)), #selector(newSessionWithCommand(_:)): connection.status == .connected
        case #selector(newThread(_:)): connection.status == .connected && connection.hasThreadList
        case #selector(closeSession(_:)): window.window.isVisible && layout.selectedRow != nil
        case #selector(renameSession(_:)): window.window.isVisible && window.sessionsList.selection != nil
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
