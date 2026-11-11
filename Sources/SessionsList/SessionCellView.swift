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
    /// The alert of a row that needs the user, or the place of the work.
    let secondLine = NSTextField(labelWithString: "")
    /// The row whose place the second line shows, cut to the width of the line.
    private var placeRow: SessionsListRow?
    let age = NSTextField(labelWithString: "")
    let attention = AttentionMarkView()
    let progress = ProgressMarkView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: Self.height))
        identifier = Self.identifier
        (imageView, textField) = (icon, title)
        icon.contentTintColor = PaneColor.quietText
        // The image starts at the edge of its view, 16 points in, where the
        // title of the list starts.
        icon.imageAlignment = .alignLeft
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        (title.font, title.textColor, title.lineBreakMode) = (.systemFont(ofSize: NSFont.systemFontSize), PaneColor.text, .byTruncatingTail)
        (secondLine.font, secondLine.textColor, secondLine.lineBreakMode) = (.systemFont(ofSize: NSFont.smallSystemFontSize), PaneColor.quietText, .byTruncatingTail)
        (age.font, age.textColor) = (.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular), PaneColor.quietText)
        secondLine.alignment = .natural
        for field in [title, secondLine] {
            field.cell?.usesSingleLineMode = true
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        age.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [icon, title, secondLine, age, attention, progress] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            secondLine.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            secondLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            secondLine.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
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
        secondLine.textColor = row.mark == .attention ? PaneColor.text : PaneColor.quietText
        placeRow = row.mark == .attention ? nil : row
        // The next layout cuts the line to its width.
        needsLayout = true
        if case .age(let text) = row.mark { age.stringValue = text } else { age.stringValue = "" }
        age.isHidden = age.stringValue.isEmpty
        attention.isHidden = row.mark != .attention
        progress.isHidden = row.mark != .progress
        toolTip = "\(row.title)\n\(row.secondLine)"
        setAccessibilityLabel(row.accessibilityLabel)
    }

    override func layout() {
        super.layout()
        fitPlace()
    }

    /// The width of the line is fixed by its constraints, so a new text does
    /// not start another layout.
    private func fitPlace() {
        guard let row = placeRow, let font = secondLine.font, secondLine.frame.width > 0 else { return }
        // A label draws its text 2 points inside each side of its frame.
        let room = secondLine.frame.width - 4
        let line = SessionsListRow.place(model: row.model, folder: row.folder, branch: row.branch) {
            NSAttributedString(string: $0, attributes: [.font: font]).size().width.rounded(.up) <= room
        }
        if secondLine.stringValue != line { secondLine.stringValue = line }
    }
}
