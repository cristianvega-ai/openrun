import AccountUsage
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
        /// A first row that is no entry: the account of the login shell.
        var fixedTitle: String?
        var fixedNote: String?
        /// The second text is a folder, which the user chooses in a panel.
        var isFolder = false
        /// The agent of an account list, as the session process names it.
        var agent: String?

        /// An empty command line starts the login shell.
        static let command = Detail(key: "command", placeholder: "Login shell", newName: "New Command", addTitle: "Add Command", hint: "An empty command starts your login shell.")

        /// - Parameters:
        ///   - program: The name of the program of the agent in a shell.
        ///   - agent: The agent as the session process names it.
        static func account(program: String, agent: String) -> Detail {
            Detail(key: "folder", newName: "New Account", addTitle: "Add Account…", hint: "An account is the folder of the settings of one login.",
                   fixedTitle: "Login of Your Shell", fixedNote: "The login that the \(program) command uses in a terminal. It needs no entry.", isFolder: true, agent: agent)
        }
    }

    struct Entry: Equatable {
        var name: String
        var detail: String
    }

    let detail: Detail
    private(set) var entries: [Entry] = []
    private(set) var entryRows: [EntryRowView] = []
    /// The usage of each account: the login of the shell first, then one
    /// line for each entry. A list of commands has none.
    private(set) var usageLines: [AccountUsageLineView] = []
    private var usage: [AccountUsageDisplay] = []
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

    /// The first row of an account list, one row for each entry, and the
    /// row with the button that adds an entry.
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
        usageLines = detail.agent == nil ? [] : (0...entries.count).map { _ in AccountUsageLineView() }
        let first = detail.fixedTitle.map { [SettingRowView(label: $0, note: detail.fixedNote, control: nil, under: usageLines.first)] } ?? []
        let entryViews = zip(entryRows, usageLines.dropFirst()).map { row, line -> NSView in
            // The usage stands under the name of the account.
            let view = NSStackView(views: [row, line])
            (view.orientation, view.alignment, view.spacing, view.edgeInsets) = (.vertical, .leading, 0, NSEdgeInsets(top: 0, left: 0, bottom: 10, right: 0))
            row.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
            line.leadingAnchor.constraint(equalTo: row.nameField.leadingAnchor).isActive = true
            return view
        }
        rows.show(first + (entryViews.isEmpty ? entryRows : entryViews) + [SettingRowView(label: "", note: detail.hint, control: addButton)])
        showUsage(usage)
    }

    /// Shows the usage of each account of the agent of the list, from the
    /// displays of every account.
    func showUsage(_ displays: [AccountUsageDisplay]) {
        usage = displays
        let names = [nil] + entries.map { Optional($0.name) }
        for (line, name) in zip(usageLines, names) {
            line.show(displays.first { $0.agent == detail.agent && $0.account == name })
        }
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

    /// Adds an entry and gives the keyboard to the field of its name. An
    /// account takes its name from its folder, such as "Work" for
    /// `.claude-work`. A number makes it a name that no other entry
    /// has, because the accounts of an agent cannot share a name.
    private func append(_ text: String) {
        let folder = detail.isFolder ? (text as NSString).lastPathComponent : ""
        let word = folder.split(separator: "-").dropFirst().joined(separator: " ").capitalized
        let base = word.isEmpty ? detail.newName : word, names = Set(entries.map { $0.name.lowercased() })
        let name = ([base] + (2...99).map { "\(base) \($0)" }).first { !names.contains($0.lowercased()) } ?? base
        entries.append(Entry(name: name, detail: text))
        makeRows()
        tell()
        entryRows.last.map { rows.window?.makeFirstResponder($0.nameField) }
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
