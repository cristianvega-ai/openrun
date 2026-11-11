import AppKit
import PaneAppearance

/// The top row of the second pane: the name of the entry and the filter,
/// and a menu for the filter and the order.
extension SessionsListController {
    func configureTopRow() {
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        (titleLabel.textColor, titleLabel.lineBreakMode) = (PaneColor.text, .byTruncatingTail)
        filterLabel.textColor = PaneColor.quietText
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        topRow.leadingItems.addArrangedSubview(titleLabel)
        topRow.leadingItems.addArrangedSubview(filterLabel)
        topRow.trailingItems.addArrangedSubview(arrangementButton)
    }

    /// The filter shows beside the name only when it hides rows.
    func updateTopRow() {
        titleLabel.stringValue = content.title
        filterLabel.stringValue = filter == .all ? "" : filter.title
        filterLabel.isHidden = filter == .all
    }

    func arrangementMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: "Show"))
        for choice in SessionsFilter.allCases {
            let item = menu.addItem(withTitle: choice.title, action: #selector(chooseFilter), keyEquivalent: "")
            (item.target, item.representedObject, item.state) = (self, choice.rawValue, choice == filter ? .on : .off)
        }
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Order By"))
        for choice in SessionsOrder.allCases {
            let item = menu.addItem(withTitle: choice.title, action: #selector(chooseOrder), keyEquivalent: "")
            (item.target, item.representedObject, item.state) = (self, choice.rawValue, choice == order ? .on : .off)
        }
        return menu
    }

    @objc func showArrangementMenu(_ sender: NSButton) {
        arrangementMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func chooseFilter(_ item: NSMenuItem) {
        guard let choice = (item.representedObject as? String).flatMap(SessionsFilter.init) else { return }
        rearrange(filter: choice, order: order)
    }

    @objc private func chooseOrder(_ item: NSMenuItem) {
        guard let choice = (item.representedObject as? String).flatMap(SessionsOrder.init) else { return }
        rearrange(filter: filter, order: choice)
    }

    /// A choice of the user, which the host keeps for the next start.
    private func rearrange(filter: SessionsFilter, order: SessionsOrder) {
        arrange(filter: filter, order: order)
        delegate?.sessionsList(self, didChange: filter, order: order)
    }
}
