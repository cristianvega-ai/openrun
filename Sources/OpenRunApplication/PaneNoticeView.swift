import AppKit
import PaneAppearance

/// A quiet notice in the middle of the third pane, with an optional button.
@MainActor
final class PaneNoticeView: NSView {
    static let minimumSize = CGSize(width: 360, height: 240)
    let title = NSTextField(labelWithString: "")
    let message = NSTextField(wrappingLabelWithString: "")
    let button = NSButton(title: "", target: nil, action: nil)
    /// Runs when the user presses the button.
    var action: (() -> Void)?

    init(_ notice: PaneNotice) {
        super.init(frame: .zero)
        title.stringValue = notice.title
        (title.font, title.textColor) = (.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold), PaneColor.text)
        message.stringValue = notice.message
        (message.font, message.textColor, message.alignment) = (.systemFont(ofSize: NSFont.smallSystemFontSize), PaneColor.quietText, .center)
        // The reason can hold a path that the user wants to copy.
        message.isSelectable = true
        (button.title, button.isHidden) = (notice.buttonTitle ?? "", notice.buttonTitle == nil)
        (button.target, button.action, button.controlSize) = (self, #selector(pressed), .small)
        let stack = NSStackView(views: [title, message, button])
        (stack.orientation, stack.alignment, stack.spacing) = (.vertical, .centerX, 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48),
            message.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PaneNoticeView does not come from a storyboard.")
    }

    @objc private func pressed() {
        action?()
    }
}
