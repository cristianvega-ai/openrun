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
        let expected: [UInt32] = [
            0x2e3134, 0xe87382, 0x9fcb8b, 0xe2c27f, 0x79aee6, 0xc59de6, 0x67c9cb, 0xc8cfd5,
            0x8a8f94, 0xf08f9b, 0xb4d8a3, 0xebd29b, 0x97c1ee, 0xd5b5ee, 0x88d8d9, 0xe6eef4,
        ]
        #expect(Array(colors.palette.prefix(16)) == expected.map(TerminalColor.init(hexadecimal:)))
        #expect(TerminalTheme.graphite(for: .dark).selection == TerminalColor(hexadecimal: 0x3a4147))
    }

    @Test func lightGraphiteGivesTheColorsOfTheTable() throws {
        let colors = try colors(of: .light)
        #expect(colors.background == TerminalColor(hexadecimal: 0xfafbfc))
        #expect(colors.foreground == TerminalColor(hexadecimal: 0x1e2022))
        #expect(colors.cursor == TerminalColor(hexadecimal: 0x1e2022))
        let expected: [UInt32] = [
            0x1e2022, 0xb8364b, 0x327339, 0x81600e, 0x2b67b1, 0x8748bc, 0x137073, 0xd6dade,
            0x6e7277, 0xce3b53, 0x3d8044, 0x8f6c15, 0x3073c5, 0x9553cb, 0x197e80, 0xf3f4f6,
        ]
        #expect(Array(colors.palette.prefix(16)) == expected.map(TerminalColor.init(hexadecimal:)))
        #expect(TerminalTheme.graphite(for: .light).selection == TerminalColor(hexadecimal: 0xdfe6ee))
    }

    @Test func colorsFromSixteenOnStayStandard() throws {
        let standard = try Terminal(size: TerminalSize(columns: 10, rows: 2), scrollbackLimit: 0).defaultPalette
        #expect(try colors(of: .dark).palette.dropFirst(16) == standard.dropFirst(16))
        #expect(try colors(of: .light).palette.dropFirst(16) == standard.dropFirst(16))
    }
}
