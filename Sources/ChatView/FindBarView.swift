import AppKit

/// The bar of Command-F at the top of the chat: a search field, the place
/// of the present match, the next and previous controls, and Done.
final class FindBarView: NSView, NSSearchFieldDelegate {
    static let height: CGFloat = 40
    let field = NSSearchField()
    let countLabel = NSTextField(labelWithString: "")
    lazy var previousButton = RowSymbol.button("arrow.up", label: "Previous Match", target: self, action: #selector(previous))
    lazy var nextButton = RowSymbol.button("arrow.down", label: "Next Match", target: self, action: #selector(next))
    lazy var doneButton = NSButton(title: "Done", target: self, action: #selector(done))
    var searchAction: ((String) -> Void)?
    /// The user asked for the next match, +1, or the previous one, -1.
    var moveAction: ((Int) -> Void)?
    var doneAction: (() -> Void)?
    private var palette: ChatPalette?

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.placeholderString = "Find in Chat"
        field.delegate = self
        (field.sendsSearchStringImmediately, field.target, field.action) = (true, self, #selector(search))
        doneButton.bezelStyle = .push
        doneButton.controlSize = .small
        countLabel.alignment = .right
        for view in [field, countLabel, previousButton, nextButton, doneButton] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    func show(matchIndex: Int?, count: Int, palette newPalette: ChatPalette) {
        palette = newPalette
        countLabel.font = newPalette.smallFont
        countLabel.textColor = newPalette.secondaryText
        countLabel.stringValue = field.stringValue.isEmpty ? "" : count == 0 ? "No matches" : "\((matchIndex ?? 0) + 1) of \(count)"
        for button in [previousButton, nextButton] {
            button.isEnabled = count > 1
            button.contentTintColor = newPalette.secondaryText
        }
        needsDisplay = true
    }

    @objc func search() { searchAction?(field.stringValue) }
    @objc func previous() { moveAction?(-1) }
    @objc func next() { moveAction?(1) }
    @objc func done() { doneAction?() }

    /// Return goes to the next match, Shift-Return to the previous one,
    /// and Escape closes the bar.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(insertNewline(_:)):
            moveAction?(NSApp?.currentEvent?.modifierFlags.contains(.shift) == true ? -1 : 1)
        case #selector(cancelOperation(_:)): doneAction?()
        default: return false
        }
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let palette else { return }
        palette.background.setFill()
        bounds.fill()
        palette.divider.setFill()
        bounds.divided(atDistance: 1, from: .maxYEdge).slice.fill()
    }

    override func layout() {
        super.layout()
        let column = ChatColumn.frame(inWidth: bounds.width)
        let doneWidth: CGFloat = 60
        doneButton.frame = NSRect(x: column.x + column.width - doneWidth, y: 8, width: doneWidth, height: 24)
        nextButton.frame = NSRect(x: doneButton.frame.minX - 32, y: 8, width: 24, height: 24)
        previousButton.frame = NSRect(x: nextButton.frame.minX - 28, y: 8, width: 24, height: 24)
        countLabel.frame = NSRect(x: previousButton.frame.minX - 88, y: 12, width: 80, height: 17)
        field.frame = NSRect(x: column.x, y: 8, width: max(80, countLabel.frame.minX - column.x - 8), height: 24)
    }
}
