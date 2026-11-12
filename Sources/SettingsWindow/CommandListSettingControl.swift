import AppKit

/// The commands of the new-session button: a table of names and command
/// lines, with a button to add an entry and one to remove the selected
/// entry. The setting is one line of JSON, as `openrun settings` shows it.
@MainActor final class CommandListSettingControl: NSObject, SettingControl, NSTableViewDataSource, NSTableViewDelegate {
    struct Entry: Codable, Equatable {
        var name: String
        var command: String
    }

    private(set) var entries: [Entry] = []
    let table = NSTableView()
    private let stack = NSStackView()
    var changed: ((String) -> Void)?
    var view: NSView { stack }

    override init() {
        super.init()
        for (identifier, title, width) in [("name", "Name", 130.0), ("command", "Command", 250.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            (column.title, column.width) = (title, width)
            table.addTableColumn(column)
        }
        (table.dataSource, table.delegate, table.usesAlternatingRowBackgroundColors) = (self, self, true)
        let scroll = NSScrollView()
        (scroll.documentView, scroll.hasVerticalScroller, scroll.borderType) = (table, true, .bezelBorder)
        scroll.heightAnchor.constraint(equalToConstant: 118).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 400).isActive = true
        let symbols = ["plus", "minus"].compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: $0 == "plus" ? "Add" : "Remove") }
        let buttons = NSSegmentedControl(images: symbols, trackingMode: .momentary, target: self, action: #selector(addOrRemove(_:)))
        (stack.orientation, stack.alignment, stack.spacing) = (.vertical, .leading, 6)
        stack.setViews([scroll, buttons], in: .leading)
    }

    func show(_ text: String) {
        entries = (try? JSONDecoder().decode([Entry].self, from: Data(text.utf8))) ?? entries
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let isName = tableColumn?.identifier.rawValue == "name"
        let field = NSTextField(string: isName ? entries[row].name : entries[row].command)
        (field.isBordered, field.drawsBackground, field.target, field.action) = (false, false, self, #selector(edited(_:)))
        // An empty command line starts the login shell.
        field.placeholderString = isName ? "" : "Login shell"
        field.tag = isName ? 0 : 1
        return field
    }

    @objc func edited(_ field: NSTextField) {
        let row = table.row(for: field)
        guard entries.indices.contains(row) else { return }
        take(row: row, isName: field.tag == 0, text: field.stringValue)
    }

    /// Takes the new text of one cell and tells the new list.
    func take(row: Int, isName: Bool, text: String) {
        let before = entries
        if isName { entries[row].name = text } else { entries[row].command = text }
        if entries != before { tell() }
    }

    @objc func addOrRemove(_ control: NSSegmentedControl) {
        if control.selectedSegment == 0 { add() } else { remove(table.selectedRow) }
    }

    func add() {
        entries.append(Entry(name: "New Command", command: ""))
        tell()
    }

    func remove(_ row: Int) {
        guard entries.indices.contains(row) else { return }
        entries.remove(at: row)
        tell()
    }

    private func tell() {
        table.reloadData()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entries) else { return }
        changed?(String(decoding: data, as: UTF8.self))
    }
}
