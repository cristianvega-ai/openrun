import AppKit

/// The rename in place, the removal and the context menu of a project.
extension ProjectsListController: NSTextFieldDelegate, NSMenuDelegate {
    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Rename", action: #selector(renameClickedProject), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Remove Project", action: #selector(removeClickedProject), keyEquivalent: "").target = self
        return menu
    }

    /// The fixed entries have no name to change and cannot go away.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        let isProject = rows.indices.contains(table.clickedRow) && rows[table.clickedRow].projectIdentifier != nil
        for item in menu.items { item.isHidden = !isProject }
    }

    @objc func renameClickedProject() {
        if let project = project(at: table.clickedRow) { beginRename(of: project) }
    }

    @objc func removeClickedProject() {
        if let project = project(at: table.clickedRow) { delegate?.projectsList(self, didRemoveProject: project) }
    }

    func renameSelectedProject() {
        if let project = project(at: table.selectedRow) { beginRename(of: project) }
    }

    func removeSelectedProject() {
        if let project = project(at: table.selectedRow) { delegate?.projectsList(self, didRemoveProject: project) }
    }

    private func project(at row: Int) -> UUID? {
        rows.indices.contains(row) ? rows[row].projectIdentifier : nil
    }

    /// Escape ends the edit and keeps the old name.
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        let row = table.row(for: control)
        if rows.indices.contains(row) { control.stringValue = rows[row].name }
        view.window?.makeFirstResponder(table)
        return true
    }

    /// Return keeps a new name that is not empty, and an empty name keeps
    /// the old one. The row shows the new name once the host has it.
    public func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        field.isEditable = false
        let row = table.row(for: field)
        guard rows.indices.contains(row), let project = rows[row].projectIdentifier else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == rows[row].name {
            field.stringValue = rows[row].name
        } else {
            delegate?.projectsList(self, didRenameProject: project, to: name)
        }
        if view.window?.firstResponder !== table { view.window?.makeFirstResponder(table) }
    }
}
