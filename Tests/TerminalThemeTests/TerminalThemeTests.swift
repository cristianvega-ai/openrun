import TerminalEmulation
import Testing
@testable import TerminalTheme

@Suite struct TerminalThemeTests {
    private func colors(of scheme: TerminalColorScheme) throws -> RenderColors {
        let terminal = try Terminal(size: TerminalSize(columns: 10, rows: 2), scrollbackLimit: 0)
        try TerminalTheme.graphite(for: scheme).apply(to: terminal)
        let state = try RenderState()
        try state.update(from: terminal)
        return state.colors
    }

    @Test func darkGraphiteGivesTheColorsOfTheTable() throws {
        let colors = try colors(of: .dark)
        #expect(colors.background == TerminalColor(hexadecimal: 0x1e2022))
        #expect(colors.foreground == TerminalColor(hexadecimal: 0xe6eef4))
        #expect(colors.cursor == TerminalColor(hexadecimal: 0xe6eef4))
        #expect(colors.palette[1] == TerminalColor(hexadecimal: 0xe87382))
        #expect(TerminalTheme.graphite(for: .dark).selection == TerminalColor(hexadecimal: 0x3a4147))
    }

    @Test func lightGraphiteGivesTheColorsOfTheTable() throws {
        let colors = try colors(of: .light)
        #expect(colors.background == TerminalColor(hexadecimal: 0xfafbfc))
        #expect(colors.foreground == TerminalColor(hexadecimal: 0x1e2022))
        #expect(colors.palette[4] == TerminalColor(hexadecimal: 0x2b67b1))
        #expect(TerminalTheme.graphite(for: .light).selection == TerminalColor(hexadecimal: 0xdfe6ee))
    }

    @Test func colorsFromSixteenOnStayStandard() throws {
        let standard = try Terminal(size: TerminalSize(columns: 10, rows: 2), scrollbackLimit: 0).defaultPalette
        #expect(try colors(of: .dark).palette.dropFirst(16) == standard.dropFirst(16))
    }
}
