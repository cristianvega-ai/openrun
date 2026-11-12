import AppKit
import Testing
import WebKit
@testable import BrowserPane

/// The web page of a split. No test uses the network: a page comes from
/// a string, and its data store leaves nothing behind.
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

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(20)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }

    @Test func anEmptyPageHasTheFocusInItsAddressAndOpensOnlyWebAddresses() {
        let (browser, window) = makeBrowser()
        defer { window.close() }
        #expect(browser.focusView === browser.addressField && browser.addressField.stringValue.isEmpty)
        #expect(!browser.backButton.isEnabled && !browser.forwardButton.isEnabled)
        #expect(browser.webView.frame.size == NSSize(width: 480, height: 320 - BrowserPaneController.barHeight))
        #expect(!browser.open("file:///etc/passwd") && !browser.open("two words") && browser.address == BrowserAddress.blank)
    }

    @Test func thePageTellsItsNewAddressAndTheFieldShowsIt() async {
        let (browser, window) = makeBrowser()
        defer { window.close() }
        var told: [String] = []
        browser.addressChanged = { told.append($0) }
        browser.webView.loadHTMLString("<title>Page</title><p>Hello</p>", baseURL: URL(string: "http://localhost:3000/docs"))
        #expect(await waitUntil { told == ["http://localhost:3000/docs"] })
        #expect(browser.address == "http://localhost:3000/docs" && browser.addressField.stringValue == "http://localhost:3000/docs")
        #expect(browser.focusView === browser.webView)
    }
}
