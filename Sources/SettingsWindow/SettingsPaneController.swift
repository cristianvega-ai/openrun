import AppKit

/// The view of one pane: a grid with the label of each setting at the
/// left and its control at the right, under the heading of its section.
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
        // Both columns are there from the start, because a heading goes over the two.
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        (grid.rowSpacing, grid.columnSpacing) = (10, 10)
        for (index, section) in pane.sections.enumerated() {
            if let title = section.title { addHeading(title, note: section.note, to: grid, isFirst: index == 0) }
            for row in section.rows { add(row, to: grid) }
        }
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 24), grid.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32), grid.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
        ])
        view = root
    }

    /// The heading of a section over both columns, with the line that
    /// tells what the section does. A section stands apart from the one
    /// over it.
    private func addHeading(_ title: String, note: String?, to grid: NSGridView, isFirst: Bool) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        var lines: [(view: NSTextField, topPadding: CGFloat)] = [(label, isFirst ? 0 : 18)]
        if let note { lines.append((Self.noteLabel(note, width: 500), -6)) }
        for line in lines {
            let row = grid.addRow(with: [line.view])
            row.mergeCells(in: NSRange(location: 0, length: 2))
            (row.cell(at: 0).xPlacement, row.topPadding) = (.leading, line.topPadding)
        }
    }

    static func noteLabel(_ note: String, width: CGFloat) -> NSTextField {
        let text = NSTextField(wrappingLabelWithString: note)
        (text.font, text.textColor, text.preferredMaxLayoutWidth) = (.systemFont(ofSize: NSFont.smallSystemFontSize), .secondaryLabelColor, width)
        return text
    }

    private func add(_ row: SettingRow, to grid: NSGridView) {
        let control = row.makeControl()
        controls[row.name] = control
        control.changed = { [weak self] text in self?.changed?(row.name, text) }
        let label = NSTextField(labelWithString: row.label.isEmpty ? "" : row.label + ":")
        let gridRow = grid.addRow(with: [label, control.view])
        // A tall control, such as a table, has its label at its top.
        gridRow.rowAlignment = control.view is NSStackView && control.view.fittingSize.height > 40 ? .none : .firstBaseline
        gridRow.yPlacement = .top
        guard let note = row.note else { return }
        grid.addRow(with: [NSGridCell.emptyContentView, Self.noteLabel(note, width: 400)]).topPadding = -4
    }

    /// Gives each control the text of its setting.
    func show(_ texts: [String: String]) {
        loadViewIfNeeded()
        for (name, control) in controls { texts[name].map(control.show) }
    }
}
