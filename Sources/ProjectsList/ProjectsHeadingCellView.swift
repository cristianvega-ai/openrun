import AppKit
import PaneAppearance

/// A row of the first pane that the user does not select: the heading of
/// the projects, or the hint of an empty list of projects.
@MainActor
final class ProjectsHeadingCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ProjectsHeadingCell")
    /// The heading stands apart from the entries over it.
    static let headingHeight: CGFloat = 38
    static let hintHeight: CGFloat = 26
    let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: Self.headingHeight))
        identifier = Self.identifier
        textField = label
        (label.textColor, label.lineBreakMode) = (PaneColor.quietText, .byTruncatingTail)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("ProjectsHeadingCellView does not come from a storyboard.")
    }

    func show(_ row: ProjectsListRow) {
        label.stringValue = row.name
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: row.kind == .heading ? .semibold : .regular)
        setAccessibilityLabel(row.name)
    }
}
