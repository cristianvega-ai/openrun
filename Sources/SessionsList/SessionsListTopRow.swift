import AppKit
import PaneAppearance

/// The top row of the second pane: the name of the entry and the filter,
/// a menu for the filter and the order, and the new-session menu.
extension SessionsListController {
    func configureTopRow() {
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        (titleLabel.textColor, titleLabel.lineBreakMode) = (PaneColor.text, .byTruncatingTail)
        filterLabel.textColor = PaneColor.quietText
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        topRow.leadingItems.addArrangedSubview(titleLabel)
        topRow.leadingItems.addArrangedSubview(filterLabel)
        topRow.trailingItems.addArrangedSubview(arrangementButton)
        topRow.trailingItems.addArrangedSubview(newSessionButton)
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

    /// A thread with each agent that the host offers, under each of its
    /// accounts, then a terminal.
    func newSessionMenu() -> NSMenu {
        let menu = NSMenu()
        // The heading tells where the new work starts, so a user sees that it belongs to the project.
        if let place = content.place { menu.addItem(.sectionHeader(title: place)) }
        for agent in content.agents {
            menu.addItem(withTitle: "New \(agent) Thread", action: #selector(requestThread), keyEquivalent: "").representedObject = [agent]
            for account in content.accounts[agent] ?? [] {
                let item = menu.addItem(withTitle: "New \(agent) Thread on \(account)", action: #selector(requestThread), keyEquivalent: "")
                item.representedObject = [agent, account]
            }
        }
        if !content.agents.isEmpty { menu.addItem(.separator()) }
        menu.addItem(withTitle: "New Terminal", action: #selector(requestTerminal), keyEquivalent: "")
        for command in content.terminalCommands {
            menu.addItem(withTitle: "New Terminal with \(command)", action: #selector(requestCommand), keyEquivalent: "").representedObject = command
        }
        for item in menu.items where item.action != nil { item.target = self }
        return menu
    }

    @objc func showArrangementMenu(_ sender: NSButton) {
        arrangementMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc func showNewSessionMenu(_ sender: NSButton) {
        newSessionMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
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

    @objc private func requestThread(_ item: NSMenuItem) {
        guard let words = item.representedObject as? [String], let agent = words.first else { return }
        delegate?.sessionsList(self, didRequest: .thread(agent: agent, account: words.dropFirst().first))
    }

    @objc func requestTerminal() {
        delegate?.sessionsList(self, didRequest: .terminal(command: nil))
    }

    @objc private func requestCommand(_ item: NSMenuItem) {
        if let command = item.representedObject as? String { delegate?.sessionsList(self, didRequest: .terminal(command: command)) }
    }
}
