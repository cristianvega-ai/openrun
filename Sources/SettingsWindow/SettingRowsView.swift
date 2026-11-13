import AppKit
import PaneAppearance

/// Rows one under the other with a thin line between two of them: the
/// rows of a card, or the entries of a list.
@MainActor final class SettingRowsView: NSStackView {
    private(set) var rows: [NSView] = []
    private var lines: [NSView] = []

    init(rows: [NSView] = []) {
        super.init(frame: .zero)
        (orientation, spacing, alignment) = (.vertical, 0, .leading)
        show(rows)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ rows: [NSView]) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        (self.rows, lines) = (rows, rows.dropFirst().map { _ in Self.line() })
        for (index, row) in rows.enumerated() {
            for view in (index > 0 ? [lines[index - 1]] : []) + [row] {
                addArrangedSubview(view)
                view.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
            }
        }
        refreshLines()
    }

    /// A line shows only between two rows that show, so a search that
    /// hides rows leaves no line at an edge.
    func refreshLines() {
        var hasRowAbove = false
        for (index, row) in rows.enumerated() {
            if index > 0 { lines[index - 1].isHidden = row.isHidden || !hasRowAbove }
            hasRowAbove = hasRowAbove || !row.isHidden
        }
    }

    static func line() -> NSView {
        let line = NSBox()
        (line.boxType, line.borderWidth, line.fillColor) = (.custom, 0, PaneColor.divider)
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }
}
