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

    /// Forgets the pages that no row holds now, such as the pages of a
    /// row whose last session ended.
    func forgetClosedBrowsers() {
        let kept = Set(layout.rows.flatMap(\.pane.browsers).map(\.identifier))
        browserPanes = browserPanes.filter { kept.contains($0.key) }
    }
}
