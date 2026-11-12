import AppKit
import WebKit

/// What the buttons and the address of a web page do, and how the row
/// follows the page.
extension BrowserPaneController {
    func connect() {
        (backButton.target, backButton.action) = (webView, #selector(WKWebView.goBack(_:)))
        (forwardButton.target, forwardButton.action) = (webView, #selector(WKWebView.goForward(_:)))
        (reloadButton.target, reloadButton.action) = (webView, #selector(WKWebView.reload(_:)))
        (addressField.target, addressField.action) = (self, #selector(typedAddress))
        (webView.navigationDelegate, webView.uiDelegate) = (self, self)
        // WebKit tells of these changes on the main thread.
        observations = [
            webView.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.pageChanged() } },
            webView.observe(\.canGoBack) { [weak self] _, _ in MainActor.assumeIsolated { self?.pageChanged() } },
            webView.observe(\.canGoForward) { [weak self] _, _ in MainActor.assumeIsolated { self?.pageChanged() } },
        ]
        pageChanged()
    }

    /// The user typed an address and pressed Return. Text that is no
    /// address stays in the field, and the page stays.
    @objc func typedAddress() {
        if open(addressField.stringValue) { view.window?.makeFirstResponder(webView) } else { NSSound.beep() }
    }

    func pageChanged() {
        (backButton.isEnabled, forwardButton.isEnabled) = (webView.canGoBack, webView.canGoForward)
        let shown = webView.url?.absoluteString ?? address
        // The field follows the page, but not while the user types in it.
        if addressField.currentEditor() == nil { addressField.stringValue = shown == BrowserAddress.blank ? "" : shown }
        guard shown != address else { return }
        address = shown
        addressChanged?(shown)
    }
}
