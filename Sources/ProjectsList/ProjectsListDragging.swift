import AppKit

/// A drag of a project to another place, and a drop of folders from Finder.
extension ProjectsListController {
    static let projectType = NSPasteboard.PasteboardType("ai.cristianvega.openrun.project-row")

    func configureDragging() {
        table.registerForDraggedTypes([Self.projectType, .fileURL])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.draggingDestinationFeedbackStyle = .gap
    }

    public func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard rows[row].projectIdentifier != nil else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: Self.projectType)
        return item
    }

    public func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if let source = draggedRow(info) {
            let first = ProjectsListRow.firstProjectRow
            let target = min(max(row, first), first + content.projects.count)
            guard ProjectMove(row: source, dropRow: target, projectCount: content.projects.count) != nil else { return [] }
            tableView.setDropRow(target, dropOperation: .above)
            return .move
        }
        guard !folders(in: info).isEmpty else { return [] }
        // A folder drop asks for a new project wherever it lands, so the whole list shows as the target.
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }

    public func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        if let source = draggedRow(info) { return moveProject(row: source, dropRow: row) }
        let folders = folders(in: info)
        guard !folders.isEmpty else { return false }
        delegate?.projectsList(self, didRequestProjectsAt: folders)
        return true
    }

    /// Moves the row at once, so the drop does not jump back while the host
    /// saves the new order, and then tells the host.
    func moveProject(row: Int, dropRow: Int) -> Bool {
        guard let move = ProjectMove(row: row, dropRow: dropRow, projectCount: content.projects.count) else { return false }
        let project = content.projects[move.source]
        content.projects.insert(content.projects.remove(at: move.source), at: move.destination)
        rows = ProjectsListRow.rows(for: content)
        table.moveRow(at: row, to: move.destinationRow)
        delegate?.projectsList(self, didMoveProject: project.identifier, toIndex: move.destination)
        return true
    }

    private func draggedRow(_ info: NSDraggingInfo) -> Int? {
        guard (info.draggingSource as? NSTableView) === table else { return nil }
        return info.draggingPasteboard.string(forType: Self.projectType).flatMap(Int.init)
    }

    /// Only folders become projects. A drop that holds a file is refused whole.
    func folders(in info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let allFolders = urls.allSatisfy { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        return allFolders ? urls : []
    }
}
