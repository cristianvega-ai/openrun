import AppKit
import MarkdownText

/// A style with fixed fonts and plain colors for the tests.
enum MarkdownTestStyle {
    static var standard: MarkdownStyle {
        MarkdownStyle(
            bodyFont: .systemFont(ofSize: 14), codeFont: .monospacedSystemFont(ofSize: 12, weight: .regular),
            textColor: .black, secondaryTextColor: .gray, linkColor: .blue, inlineCodeBackgroundColor: .lightGray,
            dividerColor: .separatorColor, tableHeaderBackgroundColor: .white)
    }
}
