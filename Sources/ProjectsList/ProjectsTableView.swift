import AppKit

/// The table of the first pane: one column of rows of one height, with no
/// header, on the color of the pane. Return starts a rename of the selected
/// project, as in the Finder, and Command-Delete removes it.
@MainActor
final class ProjectsTableView: NSTableView {
    var renameSelected: (() -> Void)?
    var removeSelected: (() -> Void)?

    init() {
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Project"))
        column.resizingMask = .autoresizingMask
        addTableColumn(column)
        headerView = nil
        style = .plain
        rowSizeStyle = .custom
        rowHeight = ProjectCellView.height
        intercellSpacing = .zero
        backgroundColor = .clear
        focusRingType = .none
        allowsEmptySelection = false
        columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        setAccessibilityLabel("Projects")
    }

    required init?(coder: NSCoder) {
        fatalError("ProjectsTableView does not come from a storyboard.")
    }

    override func keyDown(with event: NSEvent) {
        switch (event.keyCode, event.modifierFlags.intersection(.deviceIndependentFlagsMask)) {
        case (36, []), (76, []): renameSelected?()
        case (51, .command): removeSelected?()
        default: super.keyDown(with: event)
        }
    }

    /// The context menu belongs to the row under the pointer, so the click
    /// selects nothing, as in the Finder sidebar.
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        return super.menu(for: event)
    }
}
