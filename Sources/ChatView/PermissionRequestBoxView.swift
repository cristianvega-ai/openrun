import AppKit

/// The loud box of a permission request that waits: what the agent wants,
/// the command or input in full, an optional message for a denial, and
/// Deny and Allow. Only a click or the keyboard focus on a button answers.
final class PermissionRequestBoxView: RoundedBoxView, MeasurableView {
    static let padding: CGFloat = 16
    let symbol = NSImageView()
    let title = NSTextField(wrappingLabelWithString: "")
    let subjectBox = DetailBoxView()
    let messageField = NSTextField()
    lazy var denyButton = NSButton(title: "Deny", target: self, action: #selector(deny))
    lazy var allowButton = NSButton(title: "Allow", target: self, action: #selector(allow))
    var answerAction: ((ChatPermissionAnswer) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        cornerRadius = 10
        borderWidth = 1.5
        messageField.lineBreakMode = .byTruncatingTail
        for view in [symbol, title, subjectBox, messageField, denyButton, allowButton] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ words: PermissionRequestWords, agentName: String, isAnswered: Bool, palette: ChatPalette) {
        fillColor = palette.attentionBackground
        borderColor = palette.attention
        symbol.image = RowSymbol.image("hand.raised", pointSize: 15, weight: .medium)
        symbol.contentTintColor = palette.attention
        title.stringValue = words.title
        title.font = NSFont.systemFont(ofSize: palette.bodyFont.pointSize, weight: .semibold)
        title.textColor = palette.text
        subjectBox.show([(words.subject, nil)], palette: palette)
        messageField.placeholderString = "Tell \(agentName) what to do instead (optional)"
        messageField.font = palette.smallFont
        for control in [denyButton, allowButton, messageField] as [NSControl] { control.isEnabled = !isAnswered }
        needsLayout = true
    }

    @objc func allow() { answerAction?(.allow) }

    @objc func deny() {
        let message = messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        answerAction?(.deny(message: message.isEmpty ? nil : message))
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        frames(forWidth: width).buttons.maxY + Self.padding
    }

    private func frames(forWidth width: CGFloat) -> (title: NSRect, subject: NSRect, field: NSRect, buttons: NSRect) {
        let inner = width - 2 * Self.padding
        let titleSize = title.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner - 28, height: 1_000)) ?? .zero
        let titleFrame = NSRect(x: Self.padding + 28, y: Self.padding, width: inner - 28, height: max(20, ceil(titleSize.height)))
        let subject = NSRect(x: Self.padding, y: titleFrame.maxY + 10, width: inner, height: subjectBox.height(forWidth: inner))
        let field = NSRect(x: Self.padding, y: subject.maxY + 12, width: inner, height: 24)
        return (titleFrame, subject, field, NSRect(x: Self.padding, y: field.maxY + 10, width: inner, height: 28))
    }

    override func layout() {
        super.layout()
        let frames = frames(forWidth: bounds.width)
        symbol.frame = NSRect(x: Self.padding, y: frames.title.minY + 1, width: 20, height: 18)
        title.frame = frames.title
        subjectBox.frame = frames.subject
        messageField.frame = frames.field
        let buttonWidth: CGFloat = 84
        allowButton.frame = NSRect(x: frames.buttons.maxX - buttonWidth, y: frames.buttons.minY, width: buttonWidth, height: 28)
        denyButton.frame = NSRect(x: allowButton.frame.minX - buttonWidth - 8, y: frames.buttons.minY, width: buttonWidth, height: 28)
    }
}
