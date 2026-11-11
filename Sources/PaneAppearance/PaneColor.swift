import AppKit
import os
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
    /// dividers and the quiet text take the color of the text, and the
    /// selection moves a quarter of the way to the text, so each is clearly stronger.
    nonisolated static func colors(for appearance: NSAppearance, increasesContrast: Bool? = nil) -> WindowColors {
        var colors = TerminalTheme.graphite(for: scheme(of: appearance)).window
        if increasesContrast ?? isContrastIncreased(for: appearance) {
            (colors.divider, colors.quietText) = (colors.text, colors.text)
            colors.rowSelection = mix(colors.rowSelection, colors.text, share: 0.25)
            colors.inactiveRowSelection = colors.rowSelection
        }
        return colors
    }

    nonisolated static func mix(_ first: TerminalColor, _ second: TerminalColor, share: Double) -> TerminalColor {
        func channel(_ one: UInt8, _ other: UInt8) -> UInt8 { UInt8((Double(one) * (1 - share) + Double(other) * share).rounded()) }
        return TerminalColor(red: channel(first.red, second.red), green: channel(first.green, second.green), blue: channel(first.blue, second.blue))
    }

    /// A fixed Increase Contrast setting in place of the system's. The
    /// pictures of the window set it, because AppKit gives no appearance
    /// with Increase Contrast to a program.
    nonisolated static let contrastSetting = OSAllocatedUnfairLock<Bool?>(initialState: nil)

    nonisolated static func isContrastIncreased(for appearance: NSAppearance) -> Bool {
        if let setting = contrastSetting.withLock({ $0 }) { return setting }
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
