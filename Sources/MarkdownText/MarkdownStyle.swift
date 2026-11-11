import AppKit

/// The fonts and colors that Markdown shows with.
///
/// The colors can be dynamic, so one rendered text follows a change of
/// the appearance without a new render.
public struct MarkdownStyle {
    /// The font of prose. Headings, bold and italic derive from it.
    public var bodyFont: NSFont
    /// The font of code blocks and inline code.
    public var codeFont: NSFont
    public var textColor: NSColor
    /// The color of list marks and quoted text.
    public var secondaryTextColor: NSColor
    public var linkColor: NSColor
    /// The color behind inline code.
    public var inlineCodeBackgroundColor: NSColor
    /// The color of rules, the bars of quotes, and the lines of tables.
    public var dividerColor: NSColor
    public var tableHeaderBackgroundColor: NSColor
    /// The height of a line of prose as a multiple of the font's.
    public var lineHeightMultiple: CGFloat

    public init(
        bodyFont: NSFont, codeFont: NSFont, textColor: NSColor, secondaryTextColor: NSColor, linkColor: NSColor,
        inlineCodeBackgroundColor: NSColor, dividerColor: NSColor, tableHeaderBackgroundColor: NSColor,
        lineHeightMultiple: CGFloat = 1.2
    ) {
        self.bodyFont = bodyFont
        self.codeFont = codeFont
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.linkColor = linkColor
        self.inlineCodeBackgroundColor = inlineCodeBackgroundColor
        self.dividerColor = dividerColor
        self.tableHeaderBackgroundColor = tableHeaderBackgroundColor
        self.lineHeightMultiple = lineHeightMultiple
    }

    /// The font for a style of text, such as bold code.
    func font(for style: MarkdownSpan.Style, base: NSFont) -> NSFont {
        var font = style.contains(.code) ? codeFont.withSize((base.pointSize * 0.92).rounded()) : base
        var traits = font.fontDescriptor.symbolicTraits
        if style.contains(.bold) { traits.insert(.bold) }
        if style.contains(.italic) { traits.insert(.italic) }
        if traits != font.fontDescriptor.symbolicTraits {
            font = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
        }
        return font
    }

    /// The font of a heading of `level`.
    func headingFont(level: Int) -> NSFont {
        let scale: CGFloat = switch level {
        case 1: 1.4
        case 2: 1.2
        case 3: 1.07
        default: 1
        }
        let size = (bodyFont.pointSize * scale).rounded()
        let weight: NSFont.Weight = level <= 2 ? .bold : .semibold
        let descriptor = bodyFont.fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight]])
        return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
    }
}
