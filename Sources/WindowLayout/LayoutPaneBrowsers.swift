import Foundation

/// The web pages in the splits of a row.
extension LayoutPane {
    /// The pane with a new address for one of its web pages.
    public func settingAddress(_ address: String, ofBrowser identifier: UUID) -> LayoutPane {
        switch self {
        case .session, .thread: return self
        case .browser(var browser):
            if browser.identifier == identifier { browser.address = address }
            return .browser(browser)
        case .split(var split):
            split.first = split.first.settingAddress(address, ofBrowser: identifier)
            split.second = split.second.settingAddress(address, ofBrowser: identifier)
            return .split(split)
        }
    }

    /// The pane without one web page. The other half of its split takes
    /// its place.
    public func removingBrowser(_ identifier: UUID) -> LayoutPane? {
        switch self {
        case .session, .thread: return self
        case .browser(let browser): return browser.identifier == identifier ? nil : self
        case .split(var split):
            guard let first = split.first.removingBrowser(identifier) else { return split.second }
            guard let second = split.second.removingBrowser(identifier) else { return first }
            (split.first, split.second) = (first, second)
            return .split(split)
        }
    }
}

extension WindowLayout {
    /// The web page with the identifier, in any row.
    public func browser(_ identifier: UUID) -> LayoutBrowser? {
        rows.lazy.flatMap(\.pane.browsers).first { $0.identifier == identifier }
    }

    /// Puts a web page beside a session, a thread or a web page, in the
    /// row that shows it.
    ///
    /// - Returns: False when no row shows `leaf`. Nothing changes then.
    @discardableResult
    public mutating func addBrowser(_ browser: LayoutBrowser, beside leaf: UUID, direction: LayoutSplit.Direction) -> Bool {
        guard let index = rows.firstIndex(where: { $0.pane.leaves.contains(leaf) }) else { return false }
        rows[index].pane = rows[index].pane.splitting(leaf, with: .browser(browser), direction: direction)
        return true
    }

    /// Keeps the address of the page that a web page shows now.
    public mutating func setAddress(_ address: String, ofBrowser identifier: UUID) {
        for index in rows.indices { rows[index].pane = rows[index].pane.settingAddress(address, ofBrowser: identifier) }
    }

    /// The user closed a web page.
    public mutating func removeBrowser(_ identifier: UUID) {
        for index in rows.indices { rows[index].pane = rows[index].pane.removingBrowser(identifier) ?? rows[index].pane }
    }
}
