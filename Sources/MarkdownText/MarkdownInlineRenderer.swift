import AppKit

/// Gives the spans of a block their fonts, colors and links.
///
/// A link keeps its target as data: the view decides what a click does,
/// and the target shows as a tooltip, so the user sees where it goes.
enum MarkdownInlineRenderer {
    static func attributedString(
        _ text: String, isStreaming: Bool, font: NSFont, color: NSColor, style: MarkdownStyle
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for span in MarkdownInlineParser.spans(of: text, isStreaming: isStreaming) {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: style.font(for: span.style, base: font),
                .foregroundColor: color,
            ]
            if span.style.contains(.code) { attributes[.backgroundColor] = style.inlineCodeBackgroundColor }
            if span.style.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = span.link {
                attributes[.foregroundColor] = style.linkColor
                if !link.isEmpty {
                    attributes[.link] = link
                    attributes[.toolTip] = link
                }
            }
            // A line break in a paragraph stays inside the paragraph, so
            // its spacing and indentation stay the same.
            result.append(NSAttributedString(string: span.text.replacingOccurrences(of: "\n", with: "\u{2028}"), attributes: attributes))
        }
        return result
    }
}
