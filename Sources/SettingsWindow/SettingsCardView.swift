import AppKit
import PaneAppearance

/// The card of one section: a rounded sheet behind the rows of the
/// section, so a user sees which settings belong together.
@MainActor final class SettingsCardView: NSView {
    /// Each card has this width, so its lines of text end at known places.
    static let width: CGFloat = 620
    static let cornerRadius: CGFloat = 10
    let rows: SettingRowsView

    init(rows: [NSView]) {
        self.rows = SettingRowsView(rows: rows)
        super.init(frame: .zero)
        self.rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(self.rows)
        NSLayoutConstraint.activate([
            self.rows.topAnchor.constraint(equalTo: topAnchor), self.rows.bottomAnchor.constraint(equalTo: bottomAnchor),
            self.rows.leadingAnchor.constraint(equalTo: leadingAnchor), self.rows.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The view draws its colors itself, so they follow a change of the
    /// appearance with no extra step.
    override func draw(_ dirtyRect: NSRect) {
        let sheet = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        PaneColor.secondPane.setFill()
        sheet.fill()
        PaneColor.divider.setStroke()
        sheet.stroke()
    }
}
