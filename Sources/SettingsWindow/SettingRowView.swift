import AppKit
import PaneAppearance

/// One row of a card: the name of a setting and a line that tells what
/// it does at the left, and its control at the right.
@MainActor final class SettingRowView: NSStackView {
    /// The room of the words beside a control.
    static let wordsWidth: CGFloat = 330
    private(set) var label: NSTextField?
    private(set) var note: NSTextField?

    /// - Parameters:
    ///   - label: The name of the setting. A row with no name starts
    ///     with its note.
    ///   - control: The control at the right. A row with no control
    ///     gives its whole width to its words.
    init(label: String, note: String? = nil, control: NSView?) {
        super.init(frame: .zero)
        let words = NSStackView()
        (words.orientation, words.alignment, words.spacing) = (.vertical, .leading, 2)
        if !label.isEmpty {
            let name = NSTextField(labelWithString: label)
            (name.font, name.textColor, self.label) = (.systemFont(ofSize: NSFont.systemFontSize), PaneColor.text, name)
            words.addArrangedSubview(name)
            // VoiceOver says the name of the setting for its control.
            ((control as? NSStackView)?.arrangedSubviews.first ?? control)?.setAccessibilityLabel(label)
        }
        if let note {
            let text = Self.noteLabel(note, width: control == nil ? SettingsCardView.width - 28 : Self.wordsWidth)
            words.addArrangedSubview(text)
            self.note = text
        }
        // The words take the room that the control leaves.
        words.setHuggingPriority(.init(1), for: .horizontal)
        words.setHuggingPriority(.required, for: .vertical)
        control?.setContentHuggingPriority(.required, for: .horizontal)
        (control as? NSStackView)?.setHuggingPriority(.required, for: .horizontal)
        (orientation, alignment, distribution, spacing) = (.horizontal, .centerY, .fill, 16)
        edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        for view in [words, control].compactMap({ $0 }) {
            addArrangedSubview(view)
            // A row of many lines keeps the room over and under its words.
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10), view.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
            ])
        }
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Quiet text that goes on to the next line at `width`.
    static func noteLabel(_ note: String, width: CGFloat) -> NSTextField {
        let text = NSTextField(wrappingLabelWithString: note)
        (text.font, text.textColor, text.preferredMaxLayoutWidth) = (.systemFont(ofSize: 12), PaneColor.quietText, width)
        text.isSelectable = false
        return text
    }
}
