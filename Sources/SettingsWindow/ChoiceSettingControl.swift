import AppKit

/// A menu of the values of a setting, each with words for the user.
@MainActor final class ChoiceSettingControl: NSObject, SettingControl {
    let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var choices: [(value: String, title: String)]
    var changed: ((String) -> Void)?
    var view: NSView { popup }

    init(_ choices: [(value: String, title: String)]) {
        self.choices = choices
        super.init()
        popup.addItems(withTitles: choices.map(\.title))
        (popup.target, popup.action) = (self, #selector(choose))
    }

    func show(_ text: String) {
        // A value of a later build, or a font that this Mac does not have,
        // stays in the menu, so the window never shows a wrong value.
        if !choices.contains(where: { $0.value == text }) {
            choices.append((text, text))
            popup.addItem(withTitle: text)
        }
        popup.selectItem(at: choices.firstIndex { $0.value == text } ?? 0)
    }

    @objc func choose() {
        changed?(choices[popup.indexOfSelectedItem].value)
    }
}
