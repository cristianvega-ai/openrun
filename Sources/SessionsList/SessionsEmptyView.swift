import AppKit
import PaneAppearance

/// The quiet message of an empty list, with a button that offers the same
/// choices as the new-session button.
@MainActor
final class SessionsEmptyView: NSView {
    let message = NSTextField(labelWithString: "")
    let startButton = NSButton(title: "New Session", target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        (message.font, message.textColor, message.alignment) = (.systemFont(ofSize: NSFont.systemFontSize), PaneColor.quietText, .center)
        startButton.controlSize = .small
        let stack = NSStackView(views: [message, startButton])
        (stack.orientation, stack.spacing) = (.vertical, 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("SessionsEmptyView does not come from a storyboard.")
    }

    /// The message names the filter, so an empty filter does not look like an empty project.
    static func message(for filter: SessionsFilter) -> String {
        switch filter {
        case .all: "No Sessions"
        case .inProgress: "No Sessions in Progress"
        case .finished: "No Finished Sessions"
        }
    }
}
