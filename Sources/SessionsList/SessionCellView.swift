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
    /// The alert of a row that needs the user.
    let secondLine = NSTextField(labelWithString: "")
    /// The place of the work in three parts, so that only the folder gets shorter.
    let modelLabel = NSTextField(labelWithString: "")
    let folderLabel = NSTextField(labelWithString: "")
    let branchLabel = NSTextField(labelWithString: "")
    lazy var place = NSStackView(views: [modelLabel, folderLabel, branchLabel])
    let age = NSTextField(labelWithString: "")
    let attention = AttentionMarkView()
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
        for field in [title, secondLine, modelLabel, folderLabel, branchLabel] {
            field.cell?.usesSingleLineMode = true
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        for field in [modelLabel, folderLabel, branchLabel] {
            (field.font, field.textColor) = (.systemFont(ofSize: NSFont.smallSystemFontSize), PaneColor.quietText)
        }
        folderLabel.lineBreakMode = .byTruncatingHead
        folderLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        place.spacing = 0
        age.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [icon, title, secondLine, place, age, attention, progress] as [NSView] {
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
            secondLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            secondLine.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            place.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            place.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
            place.firstBaselineAnchor.constraint(equalTo: secondLine.firstBaselineAnchor),
        ])
        // The age, the dot and the arc end at one edge on the middle line of
        // the title, so the eye reads them as one column.
        for mark in [age, attention, progress] as [NSView] {
            NSLayoutConstraint.activate([
                mark.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
                mark.centerYAnchor.constraint(equalTo: title.centerYAnchor),
                mark.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 6),
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("SessionCellView does not come from a storyboard.")
    }

    func show(_ row: SessionsListRow) {
        icon.image = NSImage(systemSymbolName: row.symbol, accessibilityDescription: nil)
        if title.currentEditor() == nil { title.stringValue = row.title }
        secondLine.stringValue = row.secondLine
        secondLine.textColor = PaneColor.text
        (secondLine.isHidden, place.isHidden) = (row.mark != .attention, row.mark == .attention)
        (modelLabel.stringValue, modelLabel.isHidden) = (row.model.map { "\($0) · " } ?? "", row.model == nil)
        folderLabel.stringValue = row.folder
        (branchLabel.stringValue, branchLabel.isHidden) = (row.branch.map { " · \($0)" } ?? "", row.branch == nil)
        if case .age(let text) = row.mark { age.stringValue = text } else { age.stringValue = "" }
        age.isHidden = age.stringValue.isEmpty
        attention.isHidden = row.mark != .attention
        progress.isHidden = row.mark != .progress
        toolTip = "\(row.title)\n\(row.secondLine)"
        setAccessibilityLabel(row.accessibilityLabel)
    }
}
