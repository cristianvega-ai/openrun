import AppKit

/// The loud box of a permission request that waits: what the agent wants,
/// every part of it in full, an optional message for a denial, and Deny
/// and Allow. Only a click or the keyboard focus on a button answers.
final class PermissionRequestBoxView: RoundedBoxView, MeasurableView {
    static let padding: CGFloat = 16
    let symbol = NSImageView()
    let title = NSTextField(wrappingLabelWithString: "")
    /// The views of the parts of the request, from the top.
    private(set) var partViews: [NSView] = []
    let messageField = NSTextField()
    lazy var denyButton = NSButton(title: "Deny", target: self, action: #selector(deny))
    lazy var allowButton = NSButton(title: "Allow", target: self, action: #selector(allow))
    var answerAction: ((ChatPermissionAnswer) -> Void)?
    private var viewportHeight: CGFloat = 0
    private var codeLineHeight: CGFloat = 20

    override init(frame: NSRect) {
        super.init(frame: frame)
        cornerRadius = 10
        borderWidth = 1.5
        messageField.lineBreakMode = .byTruncatingTail
        for view in [symbol, title, messageField, denyButton, allowButton] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// - Parameter viewportHeight: The height of the transcript on the
    ///   screen. In a small pane, the boxes of text give way, so that the
    ///   heading, at least four lines and the buttons show at once.
    func show(_ words: PermissionRequestWords, agentName: String, isAnswered: Bool, palette: ChatPalette, viewportHeight: CGFloat = 0) {
        fillColor = palette.attentionBackground
        borderColor = palette.attention
        symbol.image = RowSymbol.image("hand.raised", pointSize: 15, weight: .medium)
        symbol.contentTintColor = palette.attention
        title.stringValue = words.title
        title.font = NSFont.systemFont(ofSize: palette.bodyFont.pointSize, weight: .semibold)
        title.textColor = palette.text
        for view in partViews { view.removeFromSuperview() }
        partViews = words.parts.flatMap { Self.views(of: $0, palette: palette) }
        for view in partViews { addSubview(view) }
        self.viewportHeight = viewportHeight
        codeLineHeight = ceil(palette.smallCodeFont.ascender - palette.smallCodeFont.descender + 6)
        messageField.placeholderString = "Tell \(agentName) what to do instead (optional)"
        messageField.font = palette.smallFont
        allowButton.isHidden = words.isCut
        for control in [denyButton, allowButton, messageField] as [NSControl] { control.isEnabled = !isAnswered }
        needsLayout = true
    }

    /// The views of one part. A text of many lines says how many, because
    /// its box shows only some of them at a time.
    private static func views(of part: PermissionRequestWords.Part, palette: ChatPalette) -> [NSView] {
        func note(_ text: String) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = palette.smallFont
            label.textColor = palette.secondaryText
            label.isSelectable = true
            return label
        }
        switch part {
        case .note(let text): return [note(text)]
        case .text(let text):
            let box = DetailBoxView()
            box.show([(text, nil)], palette: palette)
            let lines = text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            return (lines > 12 ? [note("\(lines) lines. Scroll in the box to read all of them.")] : []) + [box]
        case .diff(let diff):
            let box = DiffBoxView()
            box.show(diff, palette: palette)
            return [box]
        }
    }

    /// Gives each box of text the room that the pane leaves, but at least
    /// four lines, so the heading and the buttons stay in sight with them.
    private func fitBoxes(forWidth width: CGFloat) {
        guard viewportHeight > 0 else { return }
        let boxes = partViews.filter { $0 is DetailBoxView || $0 is DiffBoxView }
        let notes = partViews.filter { !boxes.contains($0) }.reduce(CGFloat(0)) { $0 + 8 + noteHeight($1, width: width) }
        let fixed = 2 * Self.padding + titleHeight(forWidth: width) + 2 + notes + CGFloat(boxes.count) * 8 + 14 + 24 + 10 + 28
        let room = (viewportHeight - 18 - RowSpacing.bottom - fixed) / CGFloat(max(1, boxes.count))
        for box in boxes {
            if let text = box as? DetailBoxView {
                text.heightLimit = max(4 * codeLineHeight, min(DetailBoxView.maximumHeight, room - 2 * DetailBoxView.padding.height))
            } else if let diff = box as? DiffBoxView {
                diff.heightLimit = max(4 * diff.linesView.lineHeight, min(DiffBoxView.maximumHeight, room - 2 * DiffBoxView.padding))
            }
        }
    }

    @objc func allow() { answerAction?(.allow) }

    @objc func deny() {
        let message = messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        answerAction?(.deny(message: message.isEmpty ? nil : message))
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        frames(forWidth: width).buttons.maxY + Self.padding
    }

    private func frames(forWidth width: CGFloat) -> (title: NSRect, parts: [NSRect], field: NSRect, buttons: NSRect) {
        let inner = width - 2 * Self.padding
        fitBoxes(forWidth: width)
        let titleFrame = NSRect(x: Self.padding + 28, y: Self.padding, width: inner - 28, height: titleHeight(forWidth: width))
        var top = titleFrame.maxY + 2
        let parts = partViews.map { view in
            let height = (view as? MeasurableView)?.height(forWidth: inner) ?? noteHeight(view, width: width)
            defer { top += height + 8 }
            return NSRect(x: Self.padding, y: top + 8, width: inner, height: height)
        }
        let field = NSRect(x: Self.padding, y: (parts.last?.maxY ?? titleFrame.maxY) + 14, width: inner, height: 24)
        return (titleFrame, parts, field, NSRect(x: Self.padding, y: field.maxY + 10, width: inner, height: 28))
    }

    private func titleHeight(forWidth width: CGFloat) -> CGFloat {
        let size = title.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width - 2 * Self.padding - 28, height: 1_000)) ?? .zero
        return max(20, ceil(size.height))
    }

    private func noteHeight(_ view: NSView, width: CGFloat) -> CGFloat {
        let bounds = NSRect(x: 0, y: 0, width: width - 2 * Self.padding, height: 10_000)
        return ceil((view as? NSTextField)?.cell?.cellSize(forBounds: bounds).height ?? 0)
    }

    override func layout() {
        super.layout()
        let frames = frames(forWidth: bounds.width)
        symbol.frame = NSRect(x: Self.padding, y: frames.title.minY + 1, width: 20, height: 18)
        title.frame = frames.title
        for (view, frame) in zip(partViews, frames.parts) { view.frame = frame }
        messageField.frame = frames.field
        let buttonWidth: CGFloat = 84
        allowButton.frame = NSRect(x: frames.buttons.maxX - buttonWidth, y: frames.buttons.minY, width: buttonWidth, height: 28)
        let denyRight = allowButton.isHidden ? frames.buttons.maxX : allowButton.frame.minX - 8
        denyButton.frame = NSRect(x: denyRight - buttonWidth, y: frames.buttons.minY, width: buttonWidth, height: 28)
    }
}
