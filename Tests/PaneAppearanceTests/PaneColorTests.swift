import AppKit
import TerminalEmulation
import TerminalTheme
import Testing
@testable import PaneAppearance

@MainActor @Suite struct PaneColorTests {
    private func components(_ color: NSColor, in name: NSAppearance.Name) throws -> [Int] {
        var resolved: NSColor?
        try #require(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        let srgb = try #require(resolved)
        return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].map { Int(($0 * 255).rounded()) }
    }

    private func channels(_ color: TerminalColor) -> [Int] { [Int(color.red), Int(color.green), Int(color.blue)] }

    @Test func eachColorFollowsTheAppearance() throws {
        for (name, scheme) in [(NSAppearance.Name.aqua, TerminalColorScheme.light), (.darkAqua, .dark)] {
            let window = TerminalTheme.graphite(for: scheme).window
            #expect(try components(PaneColor.firstPane, in: name) == channels(window.firstPane))
            #expect(try components(PaneColor.secondPane, in: name) == channels(window.secondPane))
            #expect(try components(PaneColor.quietText, in: name) == channels(window.quietText))
            #expect(try components(PaneColor.attention, in: name) == channels(window.attention))
            #expect(try components(PaneColor.terminalBackground, in: name) == channels(TerminalTheme.graphite(for: scheme).background))
        }
    }

    /// The distance of two colors from 0 to 765, as a measure of contrast.
    private func distance(_ first: TerminalColor, _ second: TerminalColor) -> Int {
        zip(channels(first), channels(second)).map { abs($0 - $1) }.reduce(0, +)
    }

    /// Increase Contrast gives the dividers and the quiet text the color of
    /// the text, and makes the selection clearly stronger.
    @Test func increaseContrastMakesTheQuietPartsStrong() throws {
        for (name, scheme) in [(NSAppearance.Name.aqua, TerminalColorScheme.light), (.darkAqua, .dark)] {
            let window = TerminalTheme.graphite(for: scheme).window
            let strong = PaneColor.colors(for: try #require(NSAppearance(named: name)), increasesContrast: true)
            #expect(strong.quietText == window.text && strong.divider == window.text && strong.text == window.text)
            #expect(distance(strong.rowSelection, window.secondPane) >= 2 * distance(window.rowSelection, window.secondPane) + 60)
            #expect(strong.inactiveRowSelection == strong.rowSelection)
            #expect(PaneColor.colors(for: try #require(NSAppearance(named: name)), increasesContrast: false) == window)
        }
    }
}
