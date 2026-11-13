import AppKit
import PaneAppearance

/// One row of the list of panes: an outline icon and the title of the
/// pane, as a row of the first pane of the main window.
@MainActor final class SettingsSidebarCellView: NSTableCellView {
    static let height: CGFloat = 30

    init(title: String, symbolName: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: Self.height))
        let icon = NSImageView(), name = NSTextField(labelWithString: title)
        (imageView, textField) = (icon, name)
        (icon.image, icon.contentTintColor) = (NSImage(systemSymbolName: symbolName, accessibilityDescription: nil), PaneColor.quietText)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        (name.font, name.textColor, name.lineBreakMode) = (.systemFont(ofSize: NSFont.systemFontSize), PaneColor.text, .byTruncatingTail)
        for view in [icon, name] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 27), name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 44),
            name.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
