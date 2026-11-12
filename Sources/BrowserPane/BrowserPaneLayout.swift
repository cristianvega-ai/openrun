import AppKit

/// Where the parts of a web page of a split are.
extension BrowserPaneController {
    func layOut() {
        let bar = NSStackView(views: [backButton, forwardButton, reloadButton, addressField])
        (bar.spacing, bar.edgeInsets) = (4, NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 10))
        (addressField.placeholderString, addressField.bezelStyle, addressField.lineBreakMode) = ("Address", .roundedBezel, .byTruncatingTail)
        addressField.cell?.usesSingleLineMode = true
        addressField.setAccessibilityLabel("Address")
        for subview in [bar, webView] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor), bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: bar.bottomAnchor), webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor), webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
}
