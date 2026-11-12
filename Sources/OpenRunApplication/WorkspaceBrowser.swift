import AppKit
import BrowserPane
import WindowLayout

/// The web pages in the splits of the third pane (decision of
/// 2026-10-15). A page belongs to the app only: no message of the socket
/// and no command of the tool reaches it, so no agent drives it.
extension Workspace {
    /// The web page of a leaf of the layout. A new page loads its address.
    func browserPane(of browser: LayoutBrowser) -> BrowserPaneController {
        if let pane = browserPanes[browser.identifier] { return pane }
        let pane = BrowserPaneController(address: browser.address, keepsWebsiteData: keepsWebsiteData)
        pane.addressChanged = { [weak self] address in self?.keepAddress(address, ofBrowser: browser.identifier) }
        browserPanes[browser.identifier] = pane
        return pane
    }

    /// A page went to another address. The layout keeps it, so the page
    /// comes back with its row.
    func keepAddress(_ address: String, ofBrowser identifier: UUID) {
        layout.setAddress(address, ofBrowser: identifier)
        // The view shows the page already, so the pane needs no new view.
        if case .split(let row, _) = shown, let pane = layout.row(row).flatMap({ living($0.pane) }) { shown = .split(row: row, pane: pane) }
        layoutStore.save(layout)
    }

    /// Opens an empty web page beside the pane with the focus. Its
    /// address field takes the focus.
    @objc func splitWithBrowser(_ sender: Any?) {
        guard let leaf = focusedLeaf else { return }
        let browser = LayoutBrowser(address: BrowserAddress.blank)
        guard layout.addBrowser(browser, beside: leaf, direction: .sideBySide) else { return }
        (leafToFocus, lastFocusedLeaf) = (browser.identifier, browser.identifier)
        layoutStore.save(layout)
        refresh()
    }

    /// Opens a web link of a session or a thread in a web page of its
    /// row, when the setting `open-links-in` asks for the browser split:
    /// in the first page of the row, or else in a new page beside the
    /// pane of the link. The keyboard focus stays where it is.
    ///
    /// - Returns: False when the link must open with the default program.
    func openInBrowserSplit(_ link: URL, from leaf: UUID) -> Bool {
        guard settings.linkDestination == .browserSplit, BrowserAddress.url(from: link.absoluteString) != nil,
              let row = layout.rows.first(where: { $0.pane.leaves.contains(leaf) }) else { return false }
        if let page = row.pane.browsers.first { return browserPane(of: page).open(link.absoluteString) }
        guard layout.addBrowser(LayoutBrowser(address: link.absoluteString), beside: leaf, direction: .sideBySide) else { return false }
        layoutStore.save(layout)
        refresh()
        return true
    }

    /// The user closed a web page. Its room goes to the other half of
    /// its split.
    func closeBrowser(_ identifier: UUID) {
        layout.removeBrowser(identifier)
        browserPanes[identifier] = nil
        layoutStore.save(layout)
        refresh()
    }

    /// Forgets the pages that no row holds now, such as the pages of a
    /// row whose last session ended.
    func forgetClosedBrowsers() {
        let kept = Set(layout.rows.flatMap(\.pane.browsers).map(\.identifier))
        browserPanes = browserPanes.filter { kept.contains($0.key) }
    }
}
