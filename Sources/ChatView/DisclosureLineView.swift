import AppKit

/// A compact line that opens to show more, such as a tool call. The line
/// itself is the control, so it needs no chevron: a click, Space or Return
/// opens it, and a quiet fill shows under the pointer.
final class DisclosureLineView: NSView {
    static let height: CGFloat = 24
    let symbol = NSImageView()
    let title = NSTextField(labelWithString: "")
    let status = NSTextField(labelWithString: "")
    var action: (() -> Void)?
    var hoverColor = NSColor.clear
    var isOpen = false {
        didSet { setAccessibilityExpanded(isOpen) }
    }
    private var isHovered = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.lineBreakMode = .byTruncatingTail
        for view in [symbol, title, status] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { action != nil }

    func show(symbolName: String, title text: String, status statusText: String?, palette: ChatPalette) {
        symbol.image = RowSymbol.image(symbolName, pointSize: 12)
        symbol.contentTintColor = palette.secondaryText
        title.stringValue = text
        title.font = palette.smallFont
        title.textColor = palette.secondaryText
        status.stringValue = statusText ?? ""
        status.font = palette.smallFont
        status.textColor = palette.secondaryText.withAlphaComponent(0.75)
        hoverColor = palette.divider.withAlphaComponent(0.5)
        setAccessibilityLabel([text, statusText].compactMap { $0 }.joined(separator: ", "))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let middle = bounds.height / 2
        symbol.frame = NSRect(x: 6, y: middle - 8, width: 16, height: 16)
        let statusWidth = status.stringValue.isEmpty ? 0 : ceil(status.attributedStringValue.size().width) + 4
        let titleWidth = min(ceil(title.attributedStringValue.size().width) + 4, bounds.width - 38 - statusWidth - (statusWidth > 0 ? 8 : 0))
        title.frame = NSRect(x: 30, y: middle - 9, width: max(0, titleWidth), height: 18)
        status.frame = NSRect(x: title.frame.maxX + 8, y: middle - 9, width: statusWidth, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered, action != nil else { return }
        hoverColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { action?() }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || event.keyCode == 36 { action?() } else { super.keyDown(with: event) }
    }

    override func accessibilityPerformPress() -> Bool {
        action?()
        return action != nil
    }

    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }
}
