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
    /// Whether the line has the keyboard focus. The line draws its own
    /// mark, as wide as its fill, so the mark follows its rounded shape.
    private(set) var showsFocusMark = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.lineBreakMode = .byTruncatingTail
        status.lineBreakMode = .byTruncatingTail
        for view in [symbol, title, status] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        focusRingType = .none
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
        // The title keeps at least 60 percent of the line, and a long
        // state, such as the message of a denial, gives way first.
        let room = max(0, bounds.width - 38)
        let wantedStatus = status.stringValue.isEmpty ? 0 : ceil(status.attributedStringValue.size().width) + 4
        let titleWidth = min(ceil(title.attributedStringValue.size().width) + 4, max(room * 0.6, room - wantedStatus - 8))
        let statusWidth = min(wantedStatus, max(0, room - titleWidth - 8))
        title.frame = NSRect(x: 30, y: middle - 9, width: titleWidth, height: 18)
        status.frame = NSRect(x: title.frame.maxX + 8, y: middle - 9, width: statusWidth, height: 18)
    }

    override func becomeFirstResponder() -> Bool {
        showsFocusMark = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        showsFocusMark = false
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard action != nil else { return }
        if isHovered {
            hoverColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        guard showsFocusMark, window?.isKeyWindow != false else { return }
        let mark = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 5, yRadius: 5)
        mark.lineWidth = 2.5
        NSColor.keyboardFocusIndicatorColor.setStroke()
        mark.stroke()
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

}
