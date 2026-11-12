import AppKit
import Testing
import WebKit
@testable import BrowserPane

@MainActor @Suite struct BrowserPaneControllerTests {
    private func makeBrowser(_ address: String = BrowserAddress.blank) -> (BrowserPaneController, NSWindow) {
        _ = NSApplication.shared
        let browser = BrowserPaneController(address: address, websiteData: .nonPersistent())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = browser.view
        window.layoutIfNeeded()
        return (browser, window)
    }

    @Test func anEmptyPageHasTheFocusInItsAddressAndOpensOnlyWebAddresses() {
        let (browser, window) = makeBrowser()
        defer { window.close() }
        #expect(browser.focusView === browser.addressField && browser.addressField.stringValue.isEmpty)
        #expect(browser.webView.frame.size == NSSize(width: 480, height: 320 - BrowserPaneController.barHeight))
        #expect(!browser.open("file:///etc/passwd") && !browser.open("two words") && browser.address == BrowserAddress.blank)
    }
}
