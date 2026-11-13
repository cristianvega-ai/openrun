import AppKit
import PaneAppearance

/// The view of one pane: its sections one under the other. A section is
/// a heading, a line that tells what the section does, and a card with
/// one row for each setting.
@MainActor final class SettingsPaneController: NSViewController {
    let pane: SettingsPane
    private(set) var controls: [String: any SettingControl] = [:]
    /// Tells the name of a setting and the new text of its value.
    var changed: ((String, String) -> Void)?

    init(_ pane: SettingsPane) {
        self.pane = pane
        super.init(nibName: nil, bundle: nil)
        title = pane.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let stack = NSStackView()
        (stack.orientation, stack.alignment, stack.spacing) = (.vertical, .leading, 4)
        for section in pane.sections { add(section, to: stack) }
        stack.widthAnchor.constraint(equalToConstant: SettingsCardView.width).isActive = true
        view = stack
    }

    private func add(_ section: SettingsSection, to stack: NSStackView) {
        var views: [NSView] = []
        if let title = section.title {
            let label = NSTextField(labelWithString: title)
            (label.font, label.textColor) = (.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold), PaneColor.text)
            views.append(label)
        }
        if let note = section.note { views.append(SettingRowView.noteLabel(note, width: SettingsCardView.width - 20)) }
        let card = SettingsCardView(rows: section.rows.map(makeView))
        for view in views + [card] { stack.addArrangedSubview(view) }
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        if let last = views.last { stack.setCustomSpacing(10, after: last) }
        // A section stands apart from the one under it.
        stack.setCustomSpacing(26, after: card)
    }

    private func makeView(of row: SettingRow) -> NSView {
        let control = row.makeControl()
        controls[row.name] = control
        control.changed = { [weak self] text in self?.changed?(row.name, text) }
        return control.isWide ? control.view : SettingRowView(label: row.label, note: row.note, control: control.view)
    }

    /// Gives each control the text of its setting.
    func show(_ texts: [String: String]) {
        loadViewIfNeeded()
        for (name, control) in controls { texts[name].map(control.show) }
    }
}
