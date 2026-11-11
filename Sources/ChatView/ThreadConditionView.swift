import AppKit

/// A condition of the thread above the composer, such as a failed start or
/// an account at its limit, with its choices.
final class ThreadConditionView: RoundedBoxView, MeasurableView {
    static let padding: CGFloat = 14
    let symbol = NSImageView()
    let title = NSTextField(wrappingLabelWithString: "")
    let detail = NSTextField(wrappingLabelWithString: "")
    private(set) var buttons: [NSButton] = []
    private var choices: [ThreadConditionWords.Choice] = []
    var choiceAction: ((ThreadConditionWords.Choice) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        cornerRadius = 10
        for view in [symbol, title, detail] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ words: ThreadConditionWords, palette: ChatPalette) {
        fillColor = palette.codeBackground
        borderColor = palette.divider
        symbol.image = RowSymbol.image(words.symbolName, pointSize: 14)
        symbol.contentTintColor = palette.secondaryText
        title.stringValue = words.title
        title.font = NSFont.systemFont(ofSize: palette.bodyFont.pointSize, weight: .semibold)
        title.textColor = palette.text
        detail.stringValue = words.detail ?? ""
        detail.font = palette.smallFont
        detail.textColor = palette.secondaryText
        buttons.forEach { $0.removeFromSuperview() }
        choices = words.choices.map(\.choice)
        buttons = words.choices.enumerated().map { index, choice in
            let button = NSButton(title: choice.title, target: self, action: #selector(choose(_:)))
            button.bezelStyle = .push
            button.tag = index
            addSubview(button)
            return button
        }
        setAccessibilityLabel([words.title, words.detail].compactMap { $0 }.joined(separator: ". "))
        needsLayout = true
    }

    @objc func choose(_ sender: NSButton) {
        choiceAction?(choices[sender.tag])
    }

    private func frames(forWidth width: CGFloat) -> (title: NSRect, detail: NSRect, buttonsTop: CGFloat, height: CGFloat) {
        let inner = width - 2 * Self.padding - 26
        func height(of field: NSTextField) -> CGFloat {
            field.stringValue.isEmpty ? 0 : ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: 1_000)).height ?? 0)
        }
        let titleFrame = NSRect(x: Self.padding + 26, y: Self.padding, width: inner, height: height(of: title))
        let detailFrame = NSRect(x: titleFrame.minX, y: titleFrame.maxY + 4, width: inner, height: height(of: detail))
        let buttonsTop = detailFrame.maxY + 10
        return (titleFrame, detailFrame, buttonsTop, buttons.isEmpty ? detailFrame.maxY + Self.padding : buttonsTop + 28 + Self.padding)
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        frames(forWidth: width).height
    }

    override func layout() {
        super.layout()
        let frames = frames(forWidth: bounds.width)
        symbol.frame = NSRect(x: Self.padding, y: frames.title.minY + 1, width: 18, height: 18)
        title.frame = frames.title
        detail.frame = frames.detail
        var x = frames.title.minX
        for button in buttons {
            let width = ceil(button.fittingSize.width) + 8
            button.frame = NSRect(x: x, y: frames.buttonsTop, width: width, height: 28)
            x += width + 8
        }
    }
}
