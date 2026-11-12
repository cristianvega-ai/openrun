import AppKit

/// The view of one pane: a grid with the label of each setting at the
/// left and its control at the right.
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
        let grid = NSGridView()
        (grid.rowSpacing, grid.columnSpacing) = (10, 10)
        for row in pane.rows {
            let control = row.makeControl()
            controls[row.name] = control
            control.changed = { [weak self] text in self?.changed?(row.name, text) }
            let label = NSTextField(labelWithString: row.label.isEmpty ? "" : row.label + ":")
            let gridRow = grid.addRow(with: [label, control.view])
            // A tall control, such as a table, has its label at its top.
            gridRow.rowAlignment = control.view is NSStackView && control.view.fittingSize.height > 40 ? .none : .firstBaseline
            gridRow.yPlacement = .top
            guard let note = row.note else { continue }
            let text = NSTextField(wrappingLabelWithString: note)
            (text.font, text.textColor, text.preferredMaxLayoutWidth) = (.systemFont(ofSize: NSFont.smallSystemFontSize), .secondaryLabelColor, 400)
            grid.addRow(with: [NSGridCell.emptyContentView, text]).topPadding = -4
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

    /// Gives each control the text of its setting.
    func show(_ texts: [String: String]) {
        loadViewIfNeeded()
        for (name, control) in controls { texts[name].map(control.show) }
    }
}
