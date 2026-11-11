import AppKit
import PaneAppearance

/// One row of the second pane: the outline icon of its kind, the title, a
/// quiet second line, and a mark at the end of the title line.
@MainActor
final class SessionCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SessionCell")
    static let height: CGFloat = 50
    let icon = NSImageView()
    let title = NSTextField(labelWithString: "")
    let secondLine = NSTextField(labelWithString: "")
    let age = NSTextField(labelWithString: "")
    let attention = NSImageView()
    let progress = ProgressMarkView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: Self.height))
        identifier = Self.identifier
        (imageView, textField) = (icon, title)
        icon.contentTintColor = PaneColor.quietText
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        (title.font, title.textColor, title.lineBreakMode) = (.systemFont(ofSize: NSFont.systemFontSize), PaneColor.text, .byTruncatingTail)
        (secondLine.font, secondLine.textColor, secondLine.lineBreakMode) = (.systemFont(ofSize: NSFont.smallSystemFontSize), PaneColor.quietText, .byTruncatingTail)
        (age.font, age.textColor) = (.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular), PaneColor.quietText)
        attention.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
        attention.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 7, weight: .regular)
        attention.contentTintColor = PaneColor.attention
        for field in [title, secondLine] {
            field.cell?.usesSingleLineMode = true
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let marks = NSStackView(views: [age, attention, progress])
        marks.setHuggingPriority(.required, for: .horizontal)
        for view in [icon, title, secondLine, marks] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            secondLine.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            secondLine.trailingAnchor.constraint(equalTo: marks.trailingAnchor),
            secondLine.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            marks.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 6),
            marks.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            marks.centerYAnchor.constraint(equalTo: title.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("SessionCellView does not come from a storyboard.")
    }

    func show(_ row: SessionsListRow) {
        icon.image = NSImage(systemSymbolName: row.symbol, accessibilityDescription: nil)
        if title.currentEditor() == nil { title.stringValue = row.title }
        secondLine.stringValue = row.secondLine
        secondLine.textColor = row.mark == .attention ? PaneColor.text : PaneColor.quietText
        if case .age(let text) = row.mark { age.stringValue = text } else { age.stringValue = "" }
        age.isHidden = age.stringValue.isEmpty
        attention.isHidden = row.mark != .attention
        progress.isHidden = row.mark != .progress
        toolTip = "\(row.title)\n\(row.secondLine)"
        setAccessibilityLabel(row.accessibilityLabel)
    }
}
