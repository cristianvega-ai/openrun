import AppKit
import MarkdownText

/// The colors and fonts of a chat as AppKit values.
///
/// Each color is dynamic: it takes the light or the dark value of the
/// appearance that it draws in, and a stronger value when Increase
/// Contrast is on. So a change of the appearance needs no new render.
struct ChatPalette {
    let appearance: ChatAppearance
    let background: NSColor
    let text: NSColor
    let secondaryText: NSColor
    let divider: NSColor
    let userMessageBackground: NSColor
    let codeBackground: NSColor
    let attention: NSColor
    /// A faint fill of the attention color behind a request.
    let attentionBackground: NSColor
    let link: NSColor
    let addedLineBackground: NSColor
    let removedLineBackground: NSColor
    let selection: NSColor
    let bodyFont: NSFont
    /// Quiet lines, such as tool calls and notices.
    let smallFont: NSFont
    let codeFont: NSFont
    let smallCodeFont: NSFont

    init(appearance: ChatAppearance) {
        self.appearance = appearance
        func color(_ pick: @escaping @Sendable (ChatColors, Bool) -> ChatColor) -> NSColor {
            Self.dynamicColor(appearance, pick)
        }
        background = color { colors, _ in colors.background }
        text = color { colors, _ in colors.text }
        secondaryText = color { colors, strong in strong ? colors.secondaryText.mixed(with: colors.text, fraction: 0.5) : colors.secondaryText }
        divider = color { colors, strong in strong ? colors.divider.mixed(with: colors.text, fraction: 0.35) : colors.divider }
        userMessageBackground = color { colors, _ in colors.userMessageBackground }
        codeBackground = color { colors, _ in colors.codeBackground }
        attention = color { colors, _ in colors.attention }
        attentionBackground = color { colors, strong in colors.background.mixed(with: colors.attention, fraction: strong ? 0.12 : 0.06) }
        link = color { colors, _ in colors.link }
        addedLineBackground = color { colors, _ in colors.background.mixed(with: colors.addedLine, fraction: 0.14) }
        removedLineBackground = color { colors, _ in colors.background.mixed(with: colors.removedLine, fraction: 0.12) }
        selection = color { colors, _ in colors.selection }
        let size = CGFloat(appearance.bodyFontSize)
        bodyFont = NSFont.systemFont(ofSize: size)
        smallFont = NSFont.systemFont(ofSize: size - 1)
        let codeSize = CGFloat(appearance.codeFontSize)
        codeFont = appearance.codeFontName.flatMap { NSFont(name: $0, size: codeSize) }
            ?? NSFont.monospacedSystemFont(ofSize: codeSize, weight: .regular)
        smallCodeFont = codeFont.withSize(codeSize - 0.5)
    }

    /// The style of Markdown in an agent's message.
    var markdownStyle: MarkdownStyle {
        MarkdownStyle(
            bodyFont: bodyFont, codeFont: codeFont, textColor: text, secondaryTextColor: secondaryText, linkColor: link,
            inlineCodeBackgroundColor: userMessageBackground, dividerColor: divider, tableHeaderBackgroundColor: codeBackground,
            lineHeightMultiple: 1.22)
    }

    /// A color that picks its value when it draws. The flag tells whether
    /// Increase Contrast is on.
    static func dynamicColor(_ appearance: ChatAppearance, _ pick: @escaping @Sendable (ChatColors, Bool) -> ChatColor) -> NSColor {
        NSColor(name: nil) { drawing in
            let isDark = drawing.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let isStrong = drawing.name == .accessibilityHighContrastAqua || drawing.name == .accessibilityHighContrastDarkAqua
            let value = pick(isDark ? appearance.dark : appearance.light, isStrong)
            return NSColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha)
        }
    }
}
