import WebKit

/// Where a page of the browser may go.
extension BrowserPaneController: WKNavigationDelegate, WKUIDelegate {
    /// A page goes only to a web address. Another scheme, such as one
    /// that starts another app, gets no answer.
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, BrowserAddress.allowsNavigation(to: url) else { return .cancel }
        return .allow
    }

    /// A link that asks for a new window opens in this page, because the
    /// browser is one split of a row.
    public func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, BrowserAddress.allowsNavigation(to: url) { webView.load(navigationAction.request) }
        return nil
    }
}
