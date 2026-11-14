import AccountUsage
import AppKit
import PaneAppearance

/// The foot of the first pane: the usage of each account that gave a
/// reading, so the user picks an account by what is left on it.
@MainActor
final class AccountUsageView: NSView {
    private let stack = NSStackView()
    private let line = NSBox()
    private(set) var accounts: [AccountUsageDisplay] = []

    init() {
        super.init(frame: .zero)
        (line.boxType, line.borderColor, line.borderWidth) = (.custom, PaneColor.divider, 1)
        (stack.orientation, stack.alignment, stack.spacing) = (.vertical, .width, 10)
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 18, bottom: 12, right: 18)
        for view in [stack, line] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: topAnchor), line.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: leadingAnchor), line.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("AccountUsageView does not come from a storyboard.")
    }

    /// Shows the accounts. With no reading, the foot takes no room.
    func show(_ accounts: [AccountUsageDisplay]) {
        guard accounts != self.accounts else { return }
        self.accounts = accounts
        stack.setViews(accounts.map(section), in: .top)
        isHidden = accounts.isEmpty
    }

    private func label(_ text: String, color: NSColor, size: CGFloat = 10) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        (label.font, label.textColor, label.lineBreakMode) = (.monospacedDigitSystemFont(ofSize: size, weight: .regular), color, .byTruncatingTail)
        return label
    }

    /// One account: its title with the time of the reading, and one
    /// line for each window.
    private func section(_ account: AccountUsageDisplay) -> NSView {
        let title = label(account.title, color: PaneColor.text, size: NSFont.smallSystemFontSize)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let heading = NSStackView(views: [title, NSView(), label(account.readTime, color: PaneColor.quietText)])
        let rows = account.windows.map { window -> NSView in
            let meter = UsageMeterView()
            (meter.fraction, meter.isAtLimit) = (window.usedFraction, window.isAtLimit)
            let name = label(window.name, color: PaneColor.quietText)
            let share = label("\(Int((window.usedFraction * 100).rounded()))%", color: window.isAtLimit ? PaneColor.attention : PaneColor.quietText)
            name.widthAnchor.constraint(equalToConstant: 34).isActive = true
            share.widthAnchor.constraint(equalToConstant: 30).isActive = true
            share.alignment = .right
            let row = NSStackView(views: [name, meter, share])
            (row.spacing, row.alignment) = (6, .centerY)
            return row
        }
        let section = NSStackView(views: [heading] + rows)
        (section.orientation, section.alignment, section.spacing) = (.vertical, .width, 4)
        section.toolTip = account.help
        section.setAccessibilityElement(true)
        section.setAccessibilityRole(.group)
        section.setAccessibilityLabel(account.help)
        return section
    }
}
