import AppKit

/// The outline SF Symbols of the chat. Each one has the color of the text
/// next to it, so no symbol draws the eye more than its words.
@MainActor enum RowSymbol {
    static func image(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    /// A borderless button that shows only a symbol, such as Copy.
    static func button(_ name: String, label: String, target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(image: image(name, pointSize: 12) ?? NSImage(), target: target, action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }
}
