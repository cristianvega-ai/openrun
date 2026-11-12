import AppKit

/// A setting that is a list of entries, each with a name and one more
/// text: the commands of the new-session button, or the other accounts of
/// an agent. A table shows them, with a button to add an entry and one to
/// remove the selected entry. The setting is one line of JSON, as
/// `openrun settings` shows it.
@MainActor final class EntryListSettingControl: NSObject, SettingControl, NSTableViewDataSource, NSTableViewDelegate {
    /// What the second text of an entry is.
    struct Detail {
        /// Its key in the JSON of the setting.
        let key: String
        let title: String
        let placeholder: String
        /// The name of an entry that the user adds.
        let newName: String

        /// An empty command line starts the login shell.
        static let command = Detail(key: "command", title: "Command", placeholder: "Login shell", newName: "New Command")
        static let settingsFolder = Detail(key: "folder", title: "Settings Folder", placeholder: "/Users/you/.claude-work", newName: "New Account")
    }

    struct Entry: Equatable {
        var name: String
        var detail: String
    }

    let detail: Detail
    private(set) var entries: [Entry] = []
    let table = NSTableView()
    private let stack = NSStackView()
    var changed: ((String) -> Void)?
    /// Asks the user for the second text of a new entry, such as the
    /// folder of an account, and gives `nil` for a cancel. With no such
    /// question, a new entry starts with an empty text.
    var chooseDetail: ((@escaping (String?) -> Void) -> Void)?
    var view: NSView { stack }

    init(_ detail: Detail = .command) {
        self.detail = detail
        super.init()
        for (identifier, title, width) in [("name", "Name", 130.0), ("detail", detail.title, 250.0)] {
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
        // The other keys of an entry, such as one of a later build, do not count.
        if let list = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [[String: Any]] {
            let shown = list.compactMap { fields -> Entry? in
                guard let name = fields["name"] as? String, let text = fields[detail.key] as? String else { return nil }
                return Entry(name: name, detail: text)
            }
            if shown.count == list.count { entries = shown }
        }
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let isName = tableColumn?.identifier.rawValue == "name"
        let field = NSTextField(string: isName ? entries[row].name : entries[row].detail)
        (field.isBordered, field.drawsBackground, field.target, field.action) = (false, false, self, #selector(edited(_:)))
        field.placeholderString = isName ? "" : detail.placeholder
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
        if isName { entries[row].name = text } else { entries[row].detail = text }
        if entries != before { tell() }
    }

    @objc func addOrRemove(_ control: NSSegmentedControl) {
        if control.selectedSegment == 0 { add() } else { remove(table.selectedRow) }
    }

    func add() {
        guard let chooseDetail else { return append("") }
        chooseDetail { [weak self] text in
            if let text { self?.append(text) }
        }
    }

    /// Adds an entry with a name that no other entry has, because the
    /// accounts of an agent cannot share a name.
    private func append(_ text: String) {
        let names = Set(entries.map { $0.name.lowercased() })
        let name = ([detail.newName] + (2...99).map { "\(detail.newName) \($0)" }).first { !names.contains($0.lowercased()) } ?? detail.newName
        entries.append(Entry(name: name, detail: text))
        tell()
    }

    /// Asks for the folder of the settings of an account. The folder of a
    /// login often has a name that starts with a dot, so the panel shows
    /// such folders.
    static func chooseFolder(_ answer: @escaping (String?) -> Void) {
        let panel = NSOpenPanel()
        (panel.canChooseDirectories, panel.canChooseFiles, panel.showsHiddenFiles, panel.prompt) = (true, false, true, "Choose")
        panel.message = "Choose the folder of the settings of the other login."
        panel.begin { answer($0 == .OK ? panel.url?.path : nil) }
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
        guard let data = try? encoder.encode(entries.map { ["name": $0.name, detail.key: $0.detail] }) else { return }
        changed?(String(decoding: data, as: UTF8.self))
    }
}
