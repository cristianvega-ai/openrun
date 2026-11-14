import AccountUsage
import AppKit
import PaneAppearance

/// The usage of one account in its row of the Accounts pane: a meter and
/// the percent for each window of its limit, and the time of the
/// reading, as the foot of the first pane shows them.
@MainActor final class AccountUsageLineView: NSStackView {
    private(set) var display: AccountUsageDisplay?

    init() {
        super.init(frame: .zero)
        (orientation, alignment, spacing) = (.horizontal, .centerY, 8)
        show(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows a reading, or that the account gave none yet. OpenRun sends
    /// no request only to get one, so only a thread gives it.
    func show(_ display: AccountUsageDisplay?) {
        guard display != self.display || arrangedSubviews.isEmpty else { return }
        self.display = display
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let display else {
            addArrangedSubview(Self.label("No usage yet. A thread of this account reads it.", color: PaneColor.quietText))
            toolTip = nil
            setAccessibilityLabel(nil)
            return
        }
        for window in display.windows {
            let meter = UsageMeterView()
            (meter.fraction, meter.isAtLimit) = (window.usedFraction, window.isAtLimit)
            meter.widthAnchor.constraint(equalToConstant: 64).isActive = true
            let share = Self.label("\(Int((window.usedFraction * 100).rounded()))%", color: window.isAtLimit ? PaneColor.attention : PaneColor.quietText)
            for view in [Self.label(window.name, color: PaneColor.quietText), meter, share] { addArrangedSubview(view) }
            setCustomSpacing(16, after: share)
        }
        addArrangedSubview(Self.label("Read at \(display.readTime)", color: PaneColor.quietText))
        toolTip = display.help
        setAccessibilityElement(true)
        setAccessibilityLabel(display.help)
    }

    private static func label(_ text: String, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        (label.font, label.textColor) = (.monospacedDigitSystemFont(ofSize: 11, weight: .regular), color)
        return label
    }
}
