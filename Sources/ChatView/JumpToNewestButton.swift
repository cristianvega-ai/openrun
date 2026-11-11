import AppKit

/// The quiet round control that shows when the user scrolled up, and goes
/// back to the newest row.
final class JumpToNewestButton: RoundedBoxView {
    static let side: CGFloat = 32
    let symbol = NSImageView()
    var action: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        cornerRadius = Self.side / 2
        symbol.image = RowSymbol.image("arrow.down", pointSize: 13, weight: .medium)
        addSubview(symbol)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Jump to Newest")
        toolTip = "Jump to Newest"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(palette: ChatPalette) {
        fillColor = palette.background
        borderColor = palette.divider
        symbol.contentTintColor = palette.secondaryText
    }

    override func layout() {
        super.layout()
        symbol.frame = bounds.insetBy(dx: 8, dy: 8)
    }

    override func mouseDown(with event: NSEvent) { action?() }

    override func accessibilityPerformPress() -> Bool {
        action?()
        return true
    }
}
