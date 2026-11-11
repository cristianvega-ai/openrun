import AppKit
import TerminalEmulation
import TerminalTheme

/// The colors of the theme as AppKit colors. Each color follows the
/// appearance of the view that draws it, so the whole window changes at once
/// with the macOS appearance (decision of 2026-10-12). The lists use no
/// accent color, only these.
@MainActor
public enum PaneColor {
    public static let firstPane = color(\.firstPane)
    public static let secondPane = color(\.secondPane)
    public static let divider = color(\.divider)
    public static let text = color(\.text)
    public static let quietText = color(\.quietText)
    public static let rowSelection = color(\.rowSelection)
    public static let inactiveRowSelection = color(\.inactiveRowSelection)
    public static let attention = color(\.attention)
    /// The background of the terminal, which the third pane also takes.
    public static let terminalBackground = NSColor(name: nil) { appearance in
        nsColor(TerminalTheme.graphite(for: scheme(of: appearance)).background)
    }

    /// The window colors for an appearance. With Increase Contrast, the
    /// quiet text and the inactive selection take the strong versions, and
    /// the dividers take the quiet text.
    nonisolated static func colors(for appearance: NSAppearance, increasesContrast: Bool? = nil) -> WindowColors {
        var colors = TerminalTheme.graphite(for: scheme(of: appearance)).window
        if increasesContrast ?? isContrastIncreased(for: appearance) {
            (colors.divider, colors.quietText) = (colors.quietText, colors.text)
            colors.inactiveRowSelection = colors.rowSelection
        }
        return colors
    }

    nonisolated static func isContrastIncreased(for appearance: NSAppearance) -> Bool {
        let names: [NSAppearance.Name] = [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]
        let match = appearance.bestMatch(from: names)
        return match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    nonisolated static func scheme(of appearance: NSAppearance) -> TerminalColorScheme {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    nonisolated static func nsColor(_ color: TerminalColor) -> NSColor {
        NSColor(srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
    }

    private static func color(_ part: KeyPath<WindowColors, TerminalColor> & Sendable) -> NSColor {
        NSColor(name: nil) { appearance in nsColor(colors(for: appearance)[keyPath: part]) }
    }
}
