import AppKit

/// The buttons of the top rows: an outline symbol in one quiet color, with
/// no border and no tile behind it (decision of 2026-10-26).
@MainActor
public enum PaneButton {
    /// - Parameters:
    ///   - symbol: The name of an SF Symbol in its outline form.
    ///   - label: The name that VoiceOver says and the help tag shows.
    public static func make(symbol: String, label: String, target: AnyObject?, action: Selector?) -> NSButton {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(configuration)
        let button = NSButton(image: image ?? NSImage(), target: target, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.contentTintColor = PaneColor.quietText
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])
        return button
    }
}
