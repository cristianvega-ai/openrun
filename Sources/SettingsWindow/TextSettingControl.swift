import AppKit

/// A field for a setting that is text, with a list of usual values when
/// the setting has some.
@MainActor final class TextSettingControl: NSObject, SettingControl {
    let field: NSTextField
    private var shown = ""
    var changed: ((String) -> Void)?
    var view: NSView { field }

    init(suggestions: [String] = [], placeholder: String = "") {
        if suggestions.isEmpty {
            field = NSTextField(string: "")
        } else {
            let box = NSComboBox()
            box.addItems(withObjectValues: suggestions)
            field = box
        }
        super.init()
        field.placeholderString = placeholder
        field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        (field.target, field.action) = (self, #selector(typed))
    }

    func show(_ text: String) {
        shown = text
        field.stringValue = text
    }

    /// Empty text is no value of a setting, so the field goes back.
    @objc func typed() {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text != shown else { return show(shown) }
        show(text)
        changed?(text)
    }
}
