import AppKit

/// Gives each block of Markdown its text for display.
///
/// Each block renders alone, with the spacing that the block before it
/// asks for, so a view can render again only the blocks that changed. The
/// result uses TextKit 1 features, such as text tables, so a view must
/// show it with TextKit 1.
public struct MarkdownRenderer {
    public var style: MarkdownStyle
    /// The indentation of one level of a list or a quote.
    public var indentation: CGFloat

    public init(style: MarkdownStyle) {
        self.style = style
        indentation = (style.bodyFont.pointSize * 1.6).rounded()
    }

    /// The text of a block without a line end. A code block gives its code
    /// alone, because a view shows code in a box of its own.
    public func attributedString(for block: MarkdownBlock, after previous: MarkdownBlock?, isStreaming: Bool = false) -> NSAttributedString {
        let paragraph = paragraphStyle(for: block, after: previous)
        let color = block.quoteDepth > 0 ? style.secondaryTextColor : style.textColor
        let result: NSMutableAttributedString
        switch block.kind {
        case .paragraph(let text):
            result = MarkdownInlineRenderer.attributedString(text, isStreaming: isStreaming, font: style.bodyFont, color: color, style: style)
        case .heading(let level, let text):
            result = MarkdownInlineRenderer.attributedString(
                text, isStreaming: isStreaming, font: style.headingFont(level: level), color: color, style: style)
        case .listItem(let marker, let text):
            result = marks.mark(marker, depth: block.listDepth)
            result.append(MarkdownInlineRenderer.attributedString(text, isStreaming: isStreaming, font: style.bodyFont, color: color, style: style))
        case .code(_, let text, _):
            return codeAttributedString(text)
        case .table(let table):
            return MarkdownTableRenderer(style: style, isStreaming: isStreaming).attributedString(table, spacingBefore: paragraph.paragraphSpacingBefore)
        case .rule:
            return marks.rule(spacingBefore: paragraph.paragraphSpacingBefore)
        }
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }

    /// Code in the code font, with no wrap: a view scrolls long lines.
    public func codeAttributedString(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.1
        paragraph.lineBreakMode = .byClipping
        return NSAttributedString(string: text, attributes: [.font: style.codeFont, .foregroundColor: style.textColor, .paragraphStyle: paragraph])
    }

    /// The line end between a rendered block and the next one. It takes
    /// the paragraph style of the block, because TextKit reads the style of
    /// a paragraph from all of it, its line end too.
    public static func separator(after block: NSAttributedString) -> NSAttributedString {
        guard block.length > 0 else { return NSAttributedString(string: "\n") }
        var attributes = block.attributes(at: block.length - 1, effectiveRange: nil)
        for key in [NSAttributedString.Key.attachment, .link, .toolTip, .backgroundColor, .strikethroughStyle] {
            attributes[key] = nil
        }
        return NSAttributedString(string: "\n", attributes: attributes)
    }

    /// The space above a block, which depends on the block before it.
    public func spacing(before block: MarkdownBlock, after previous: MarkdownBlock?) -> CGFloat {
        guard let previous, !block.continuesParagraph else { return 0 }
        let size = style.bodyFont.pointSize
        switch (previous.kind, block.kind) {
        case (_, .heading(let level, _)): return (size * (level <= 2 ? 1.4 : 1.1)).rounded()
        case (.heading, _): return (size * 0.45).rounded()
        case (.listItem, .listItem), (.listItem, .paragraph) where block.listDepth > 0: return (size * 0.3).rounded()
        default: return (size * 0.75).rounded()
        }
    }

    private var marks: MarkdownBlockMarks {
        MarkdownBlockMarks(style: style, indentation: indentation)
    }

    func paragraphStyle(for block: MarkdownBlock, after previous: MarkdownBlock?) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = style.lineHeightMultiple
        paragraph.paragraphSpacingBefore = spacing(before: block, after: previous)
        let indent = indentation * CGFloat(block.listDepth)
        paragraph.headIndent = indent
        paragraph.firstLineHeadIndent = indent
        if case .listItem = block.kind {
            paragraph.firstLineHeadIndent = indent - indentation
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
            paragraph.defaultTabInterval = indentation
        }
        if block.quoteDepth > 0 { paragraph.textBlocks = [marks.quoteBlock(depth: block.quoteDepth)] }
        return paragraph
    }
}
