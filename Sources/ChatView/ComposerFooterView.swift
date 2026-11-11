import AppKit

/// The line under the composer: the menus of the model and the mode, and
/// the folder and the branch as quiet text. Each fact shows only here.
final class ComposerFooterView: NSView {
    static let height: CGFloat = 26
    let modelButton = ChoiceMenuButton(label: "Model")
    let modeButton = ChoiceMenuButton(label: "Permission Mode")
    let placeLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        placeLabel.lineBreakMode = .byTruncatingHead
        placeLabel.alignment = .right
        for view in [modelButton, modeButton, placeLabel] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func show(_ facts: ChatThreadFacts, palette: ChatPalette) {
        modelButton.show(facts.models, current: facts.model, palette: palette)
        modeButton.show(facts.permissionModes, current: facts.permissionMode, palette: palette)
        let text = NSMutableAttributedString()
        let attributes: [NSAttributedString.Key: Any] = [.font: palette.smallFont, .foregroundColor: palette.secondaryText]
        for (symbol, value) in [("folder", facts.folder), ("arrow.triangle.branch", facts.branch)] {
            guard let value else { continue }
            if text.length > 0 { text.append(NSAttributedString(string: "   ", attributes: attributes)) }
            if let image = RowSymbol.image(symbol, pointSize: 10) {
                let attachment = NSTextAttachment()
                attachment.image = image
                text.append(NSAttributedString(attachment: attachment))
                text.addAttribute(.foregroundColor, value: palette.secondaryText, range: NSRange(location: text.length - 1, length: 1))
                text.append(NSAttributedString(string: " ", attributes: attributes))
            }
            text.append(NSAttributedString(string: value, attributes: attributes))
        }
        placeLabel.attributedStringValue = text
        placeLabel.setAccessibilityLabel([facts.folder.map { "Folder \($0)" }, facts.branch.map { "branch \($0)" }].compactMap { $0 }.joined(separator: ", "))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for button in [modelButton, modeButton] where !button.isHidden {
            let width = ceil(button.attributedTitle.size().width) + 12
            button.frame = NSRect(x: x, y: 2, width: width, height: 22)
            x += width + 4
        }
        placeLabel.frame = NSRect(x: x + 8, y: 5, width: max(0, bounds.width - x - 14), height: 17)
    }
}
