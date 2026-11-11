import AppKit

/// A quiet button with the name of a choice, such as the model, that opens
/// a menu of the choices. The words alone are the control, with no chevron.
final class ChoiceMenuButton: NSButton {
    private(set) var choices: [ChatChoice] = []
    private(set) var current: ChatChoice?
    var selectAction: ((ChatChoice) -> Void)?
    private var label = ""

    convenience init(label: String) {
        self.init(frame: .zero)
        self.label = label
        isBordered = false
        target = self
        action = #selector(openMenu)
        setAccessibilityLabel(label)
    }

    func show(_ newChoices: [ChatChoice], current newCurrent: ChatChoice?, palette: ChatPalette) {
        choices = newChoices
        current = newCurrent
        attributedTitle = NSAttributedString(string: newCurrent?.title ?? "", attributes: [
            .font: palette.smallFont, .foregroundColor: palette.secondaryText,
        ])
        isEnabled = newChoices.count > 1
        isHidden = newCurrent == nil
        setAccessibilityValue(newCurrent?.title)
        toolTip = label
    }

    /// The menu of the choices, with a check at the present one.
    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: label)
        for choice in choices {
            let item = NSMenuItem(title: choice.title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.identifier
            item.state = choice == current ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openMenu() {
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
    }

    @objc func choose(_ item: NSMenuItem) {
        guard let choice = choices.first(where: { $0.identifier == item.representedObject as? String }) else { return }
        selectAction?(choice)
    }
}
