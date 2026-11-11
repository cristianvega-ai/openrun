import Foundation
import TerminalEmulation
import Testing
@testable import TerminalTheme

@Suite struct WindowColorsTests {
    /// The contrast ratio of the Web Content Accessibility Guidelines, from 1 to 21.
    private func contrast(_ first: TerminalColor, _ second: TerminalColor) -> Double {
        func luminance(_ color: TerminalColor) -> Double {
            func channel(_ value: UInt8) -> Double {
                let part = Double(value) / 255
                return part <= 0.03928 ? part / 12.92 : pow((part + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
        }
        let (lighter, darker) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (lighter + 0.05) / (darker + 0.05)
    }

    @Test func thePanesHaveTheColorsOfTheTable() {
        let light = TerminalTheme.graphite(for: .light).window, dark = TerminalTheme.graphite(for: .dark).window
        #expect([light.firstPane, light.secondPane, light.divider] == [0xeceef0, 0xf3f4f6, 0xdcdfe2].map(TerminalColor.init(hexadecimal:)))
        #expect([dark.firstPane, dark.secondPane, dark.divider] == [0x272a2c, 0x232628, 0x323437].map(TerminalColor.init(hexadecimal:)))
    }

    /// Small text needs a contrast of at least 4.5 to 1 (level AA), also the
    /// quiet second line and the mark of a row that needs the user, on each
    /// pane and on each selection.
    @Test(arguments: [TerminalColorScheme.light, .dark])
    func listTextIsReadableOnEveryBackgroundOfTheLists(scheme: TerminalColorScheme) {
        let colors = TerminalTheme.graphite(for: scheme).window
        for background in [colors.firstPane, colors.secondPane, colors.rowSelection, colors.inactiveRowSelection] {
            for text in [colors.text, colors.quietText, colors.attention] {
                #expect(contrast(text, background) >= 4.5, "\(text) on \(background)")
            }
        }
    }

    @Test(arguments: [TerminalColorScheme.light, .dark])
    func theQuietTextIsQuieterThanTheText(scheme: TerminalColorScheme) {
        let colors = TerminalTheme.graphite(for: scheme).window
        #expect(contrast(colors.quietText, colors.secondPane) < contrast(colors.text, colors.secondPane))
        #expect(contrast(colors.inactiveRowSelection, colors.secondPane) < contrast(colors.rowSelection, colors.secondPane))
    }
}
