import AppKit
import PaneAppearance

/// One entry of a list setting: the field of its name, its second text,
/// and the button that removes the entry.
@MainActor final class EntryRowView: NSStackView {
    let nameField: NSTextField
    /// A field for a command. For a folder it is a label, because the
    /// user chooses a folder in a panel.
    let detailField: NSTextField
    /// Tells a new text of the name, or of the second text.
    var edited: ((_ isName: Bool, _ text: String) -> Void)?
    var choose: (() -> Void)?
    var remove: (() -> Void)?

    init(name: String, detail: String, placeholder: String, isFolder: Bool) {
        nameField = NSTextField(string: name)
        detailField = isFolder ? NSTextField(labelWithString: (detail as NSString).abbreviatingWithTildeInPath) : NSTextField(string: detail)
        super.init(frame: .zero)
        (orientation, alignment, distribution, spacing) = (.horizontal, .centerY, .fill, 10)
        edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 8)
        (nameField.placeholderString, detailField.placeholderString) = ("Name", placeholder)
        nameField.widthAnchor.constraint(equalToConstant: 150).isActive = true
        for (tag, field) in [nameField, detailField].enumerated() {
            (field.tag, field.target, field.action, field.lineBreakMode) = (tag, self, #selector(typed(_:)), .byTruncatingMiddle)
            field.cell?.usesSingleLineMode = true
            addArrangedSubview(field)
        }
        detailField.setContentHuggingPriority(.init(1), for: .horizontal)
        detailField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if isFolder {
            (detailField.textColor, detailField.toolTip) = (PaneColor.quietText, detail)
            addArrangedSubview(NSButton(title: "Choose…", target: self, action: #selector(chooseDetail)))
        }
        addArrangedSubview(PaneButton.make(symbol: "trash", label: "Remove", target: self, action: #selector(removeEntry)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc func typed(_ field: NSTextField) { edited?(field.tag == 0, field.stringValue) }
    @objc func chooseDetail() { choose?() }
    @objc func removeEntry() { remove?() }
}
