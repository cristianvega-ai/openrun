import AppKit

/// The marks around blocks: the marks of list items, the bar of a quote,
/// and a rule.
struct MarkdownBlockMarks {
    let style: MarkdownStyle
    /// The indentation of one level of a list or a quote.
    let indentation: CGFloat

    /// The mark of a list item and the tab to its text.
    func mark(_ marker: MarkdownListMarker, depth: Int) -> NSMutableAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [.font: style.bodyFont, .foregroundColor: style.secondaryTextColor]
        switch marker {
        case .bullet:
            let bullets = ["•", "◦", "▪︎"]
            return NSMutableAttributedString(string: bullets[(max(depth, 1) - 1) % bullets.count] + "\t", attributes: attributes)
        case .number(let number):
            return NSMutableAttributedString(string: "\(number).\t", attributes: attributes.merging([.font: monospacedDigits]) { $1 })
        case .task(let isDone):
            let result = NSMutableAttributedString()
            if let image = NSImage(systemSymbolName: isDone ? "checkmark.square" : "square", accessibilityDescription: isDone ? "Done" : "Not done") {
                let configured = image.withSymbolConfiguration(
                    NSImage.SymbolConfiguration(pointSize: style.bodyFont.pointSize * 0.9, weight: .regular)
                        .applying(NSImage.SymbolConfiguration(paletteColors: [style.secondaryTextColor]))) ?? image
                let attachment = NSTextAttachment()
                attachment.image = configured
                let height = style.bodyFont.capHeight + 3
                let width = configured.size.height > 0 ? configured.size.width * height / configured.size.height : height
                attachment.bounds = NSRect(x: 0, y: -1.5, width: width, height: height)
                result.append(NSAttributedString(attachment: attachment))
            }
            result.append(NSAttributedString(string: "\t", attributes: attributes))
            return result
        }
    }

    private var monospacedDigits: NSFont {
        NSFont(descriptor: style.bodyFont.fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]],
        ]), size: style.bodyFont.pointSize) ?? style.bodyFont
    }

    /// A bar at the left of quoted text. Each level of depth moves the
    /// bar further in.
    func quoteBlock(depth: Int) -> NSTextBlock {
        let block = NSTextBlock()
        // A block without a width takes the width of its content, one
        // character at a time.
        block.setValue(100, type: .percentageValueType, for: .width)
        block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
        block.setBorderColor(style.dividerColor, for: .minX)
        block.setWidth(indentation * 0.55, type: .absoluteValueType, for: .padding, edge: .minX)
        block.setWidth(indentation * CGFloat(depth - 1), type: .absoluteValueType, for: .margin, edge: .minX)
        return block
    }

    /// A thin line across the text.
    func rule(spacingBefore: CGFloat) -> NSAttributedString {
        let block = NSTextBlock()
        block.setValue(100, type: .percentageValueType, for: .width)
        block.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
        block.setBorderColor(style.dividerColor, for: .maxY)
        block.setWidth(spacingBefore, type: .absoluteValueType, for: .margin, edge: .minY)
        block.setWidth(style.bodyFont.pointSize * 0.5, type: .absoluteValueType, for: .margin, edge: .maxY)
        let paragraph = NSMutableParagraphStyle()
        paragraph.textBlocks = [block]
        paragraph.minimumLineHeight = 1
        paragraph.maximumLineHeight = 1
        return NSAttributedString(string: "\u{200B}", attributes: [.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: paragraph])
    }
}
