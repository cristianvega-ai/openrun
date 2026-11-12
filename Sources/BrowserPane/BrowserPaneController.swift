import AppKit
import PaneAppearance
import WebKit

/// A web page in a split of the third pane: a web view under a row with
/// Back, Forward, Reload and the address (decision of 2026-10-15). No
/// program and no agent drives the page: only the user does.
@MainActor
public final class BrowserPaneController: NSObject {
    public static let minimumSize = CGSize(width: 320, height: 200)
    static let barHeight: CGFloat = 36

    public let view = PaneBackgroundView(color: PaneColor.secondPane)
    let webView: WKWebView
    let addressField = NSTextField()
    let backButton: NSButton
    let forwardButton: NSButton
    let reloadButton: NSButton
    /// The address of the page that shows, which the host keeps.
    public internal(set) var address: String
    /// Runs when the page has another address.
    public var addressChanged: ((String) -> Void)?
    var observations: [NSKeyValueObservation] = []

    /// - Parameter websiteData: Where the pages keep their data, such as
    ///   a login. The app uses its own lasting store, and a test uses one
    ///   that leaves nothing behind.
    public init(address: String, websiteData: WKWebsiteDataStore = .default()) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteData
        webView = WKWebView(frame: .zero, configuration: configuration)
        backButton = PaneButton.make(symbol: "chevron.left", label: "Back", target: nil, action: nil)
        forwardButton = PaneButton.make(symbol: "chevron.right", label: "Forward", target: nil, action: nil)
        reloadButton = PaneButton.make(symbol: "arrow.clockwise", label: "Reload", target: nil, action: nil)
        self.address = address
        super.init()
        layOut()
        connect()
        if let url = BrowserAddress.url(from: address) { webView.load(URLRequest(url: url)) }
    }

    /// The view that takes the keyboard focus when the pane gets it: the
    /// address of an empty page, or else the page.
    public var focusView: NSView { address == BrowserAddress.blank ? addressField : webView }

    /// Opens an address, such as a link that the user chose in a terminal.
    ///
    /// - Returns: False when the browser does not open the address.
    @discardableResult
    public func open(_ text: String) -> Bool {
        guard let url = BrowserAddress.url(from: text) else { return false }
        webView.load(URLRequest(url: url))
        return true
    }
}
