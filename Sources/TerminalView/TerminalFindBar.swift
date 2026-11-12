import AppKit
import TerminalEmulation

/// The bar of Find in a terminal (Command-F): a search field, the place of
/// the selected match among the matches, the two steps, and Done. It
/// stands at the top right of the terminal.
@MainActor final class TerminalFindBar: NSVisualEffectView, NSSearchFieldDelegate {
    static let size = NSSize(width: 360, height: 36)
    let field = NSSearchField()
    let countLabel = NSTextField(labelWithString: "")
    /// Tells the text of the field after each change.
    var textChanged: ((String) -> Void)?
    /// Tells a step: true goes to the older match.
    var move: ((_ older: Bool) -> Void)?
    var done: (() -> Void)?

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        (material, blendingMode, state) = (.menu, .withinWindow, .active)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        (field.delegate, field.placeholderString, field.sendsSearchStringImmediately) = (self, "Find", true)
        (field.target, field.action) = (self, #selector(typed))
        (countLabel.font, countLabel.textColor, countLabel.alignment) = (.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .secondaryLabelColor, .right)
        let older = button("chevron.up", "Older Match", #selector(goOlder)), newer = button("chevron.down", "Newer Match", #selector(goNewer))
        let close = button("xmark", "Done", #selector(finish))
        let stack = NSStackView(views: [field, countLabel, older, newer, close])
        (stack.spacing, stack.edgeInsets) = (6, NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8))
        stack.frame = bounds
        stack.autoresizingMask = [.width, .height]
        countLabel.widthAnchor.constraint(equalToConstant: 76).isActive = true
        addSubview(stack)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func button(_ symbol: String, _ label: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(), target: self, action: action)
        (button.isBordered, button.toolTip) = (false, label)
        return button
    }

    /// Shows where the selected match is, such as "2 of 9".
    func show(_ matches: TerminalSearch.Matches) {
        countLabel.stringValue = if field.stringValue.isEmpty { "" } else if let selected = matches.selected { "\(selected) of \(matches.count)" } else { "No matches" }
    }

    @objc func typed() { textChanged?(field.stringValue) }
    @objc func goOlder() { move?(true) }
    @objc func goNewer() { move?(false) }
    @objc func finish() { done?() }

    /// Return goes to the older match, Shift-Return to the newer one, and Escape ends Find.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        switch command {
        case #selector(NSResponder.insertNewline(_:)): move?(NSApp.currentEvent?.modifierFlags.contains(.shift) != true)
        case #selector(NSResponder.cancelOperation(_:)): done?()
        default: return false
        }
        return true
    }
}
