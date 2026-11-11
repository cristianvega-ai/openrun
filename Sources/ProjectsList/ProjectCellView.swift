import AppKit
import PaneAppearance

/// One row of the first pane: an outline icon, the name, and a quiet count
/// of the rows that need the user.
@MainActor
final class ProjectCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("ProjectCell")
    static let height: CGFloat = 30
    let icon = NSImageView()
    let name = NSTextField(labelWithString: "")
    let count = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: Self.height))
        identifier = Self.identifier
        imageView = icon
        textField = name
        icon.contentTintColor = PaneColor.quietText
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        (name.font, name.textColor, name.lineBreakMode) = (.systemFont(ofSize: NSFont.systemFontSize), PaneColor.text, .byTruncatingTail)
        name.cell?.usesSingleLineMode = true
        (count.font, count.textColor, count.alignment) = (.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular), PaneColor.quietText, .right)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        count.setContentHuggingPriority(.required, for: .horizontal)
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [icon, name, count] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            // The cut name can draw 2 points past its alignment rectangle,
            // so 10 points here keep 8 visible points before the count.
            count.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 10),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            count.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("ProjectCellView does not come from a storyboard.")
    }

    func show(_ row: ProjectsListRow) {
        icon.image = NSImage(systemSymbolName: row.symbol, accessibilityDescription: nil)
        if name.currentEditor() == nil { name.stringValue = row.name }
        count.stringValue = row.attentionCount > 0 ? "\(row.attentionCount)" : ""
        toolTip = row.help
        setAccessibilityLabel(row.accessibilityLabel)
    }
}
