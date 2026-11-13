import AppKit

/// A setting that is a list of entries, each with a name and one more
/// text: the commands of the new-session button, or the other accounts of
/// an agent. Each entry is a row, and the last row adds an entry. The
/// setting is one line of JSON, as `openrun settings` shows it.
@MainActor final class EntryListSettingControl: NSObject, SettingControl {
    /// What the second text of an entry is.
    struct Detail {
        /// Its key in the JSON of the setting.
        let key: String
        var placeholder = ""
        /// The name of an entry that the user adds.
        let newName: String
        /// The words of the button that adds an entry, and the line beside it.
        let addTitle: String
        let hint: String
        /// The second text is a folder, which the user chooses in a panel.
        var isFolder = false

        /// An empty command line starts the login shell.
        static let command = Detail(key: "command", placeholder: "Login shell", newName: "New Command", addTitle: "Add Command", hint: "An empty command starts your login shell.")

        static let settingsFolder = Detail(key: "folder", newName: "New Account", addTitle: "Add Account…", hint: "An account is the folder of the settings of one login.", isFolder: true)
    }

    struct Entry: Equatable {
        var name: String
        var detail: String
    }

    let detail: Detail
    private(set) var entries: [Entry] = []
    private(set) var entryRows: [EntryRowView] = []
    let addButton: NSButton
    private let rows = SettingRowsView()
    var changed: ((String) -> Void)?
    /// Asks the user for the second text of an entry, such as the folder
    /// of an account, and gives `nil` for a cancel. With no such
    /// question, a new entry starts with an empty text.
    var chooseDetail: ((@escaping (String?) -> Void) -> Void)?
    var view: NSView { rows }
    var isWide: Bool { true }

    init(_ detail: Detail = .command) {
        self.detail = detail
        addButton = NSButton(title: detail.addTitle, target: nil, action: nil)
        super.init()
        (addButton.target, addButton.action) = (self, #selector(add))
        makeRows()
    }

    func show(_ text: String) {
        guard let list = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [[String: Any]] else { return }
        let shown = list.compactMap { fields -> Entry? in
            guard let name = fields["name"] as? String, let text = fields[detail.key] as? String else { return nil }
            return Entry(name: name, detail: text)
        }
        // The other keys of an entry, such as one of a later build, do not count.
        // The same entries keep their rows, so a field that the user types in keeps the keyboard.
        guard shown.count == list.count, shown != entries else { return }
        entries = shown
        makeRows()
    }

    /// One row for each entry, and the row with the button that adds an entry.
    private func makeRows() {
        entryRows = entries.indices.map { index in
            let row = EntryRowView(name: entries[index].name, detail: entries[index].detail, placeholder: detail.placeholder, isFolder: detail.isFolder)
            row.edited = { [weak self] isName, text in self?.take(row: index, isName: isName, text: text) }
            row.remove = { [weak self] in self?.remove(index) }
            row.choose = { [weak self] in
                self?.chooseDetail? { text in text.map { self?.take(row: index, isName: false, text: $0) } }
            }
            return row
        }
        rows.show(entryRows + [SettingRowView(label: "", note: detail.hint, control: addButton)])
    }

    /// Takes the new text of one field and tells the new list.
    func take(row: Int, isName: Bool, text: String) {
        guard entries.indices.contains(row) else { return }
        let before = entries
        if isName { entries[row].name = text } else { entries[row].detail = text }
        guard entries != before else { return }
        // A new folder shows in the label of its row.
        if !isName { makeRows() }
        tell()
    }

    @objc func add() {
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
        makeRows()
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
        makeRows()
        tell()
    }

    private func tell() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entries.map { ["name": $0.name, detail.key: $0.detail] }) else { return }
        changed?(String(decoding: data, as: UTF8.self))
    }
}
