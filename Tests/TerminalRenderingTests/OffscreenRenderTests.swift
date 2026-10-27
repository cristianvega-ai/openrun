import Metal
import Testing
import TerminalEmulation
import TerminalTheme
@testable import TerminalRendering

@Suite struct OffscreenRenderTests {
    @Test func anOffscreenTargetGivesItsPixelsAndWritesAPNGFile() throws {
        let target = try OffscreenTarget(device: #require(MTLCreateSystemDefaultDevice()), width: 4, height: 3)
        var bytes: [UInt8] = [0x03, 0x02, 0x01, 0xFF]
        target.texture.replace(region: MTLRegionMake2D(2, 1, 1, 1), mipmapLevel: 0, withBytes: &bytes, bytesPerRow: 4)
        #expect(target.pixel(x: 2, y: 1) == TerminalColor(red: 1, green: 2, blue: 3))
        let url = FileManager.default.temporaryDirectory.appending(path: "offscreen-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try target.savePNG(to: url)
        #expect(try Data(contentsOf: url).starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test(arguments: [TerminalColorScheme.dark, .light])
    func aBlankScreenHasTheGraphiteBackgroundOfTheAppearance(scheme: TerminalColorScheme) throws {
        let screen = try renderScreen("", scheme: scheme)
        #expect(middle(of: screen.target, column: 3, row: 1) == screen.theme.background)
        #expect(screen.target.pixel(x: 0, y: 0) == screen.theme.background)
    }

    @Test func aCellBackgroundHasItsColorOfThePalette() throws {
        let screen = try renderScreen("\u{1B}[41m ")
        #expect(middle(of: screen.target, column: 0, row: 0) == screen.theme.firstSixteenColors[1])
        #expect(middle(of: screen.target, column: 1, row: 0) == screen.theme.background)
    }

    @Test(arguments: [TerminalColorScheme.dark, .light])
    func aFullBlockHasTheGraphiteTextColor(scheme: TerminalColorScheme) throws {
        let screen = try renderScreen("█", scheme: scheme)
        #expect(middle(of: screen.target, column: 0, row: 0) == screen.theme.foreground)
    }

    @Test func aWideCharacterCoversItsTwoCellsAndNoMore() throws {
        let screen = try renderScreen("\u{1B}[?25l日", columns: 6)
        #expect(inkCount(of: screen, columns: 0..<2, rows: 0..<1) > 100)
        #expect(inkCount(of: screen, columns: 2..<6, rows: 0..<3) == 0)
    }

    @Test func anEmojiHasItsOwnColorsAndStaysInsideItsTwoCells() throws {
        let screen = try renderScreen("\u{1B}[?25l🙂", columns: 6)
        let yellow = (0..<2 * testFonts.cellWidth).flatMap { x in (0..<testFonts.cellHeight).map { (x, $0) } }
            .map { screen.target.pixel(x: testPadding + $0, y: testPadding + $1) }.filter { Int($0.red) > Int($0.blue) + 80 }
        #expect(yellow.count > 50)
        #expect(inkCount(of: screen, columns: 0..<2, rows: 0..<1) > 100)
        #expect(inkCount(of: screen, columns: 2..<6, rows: 0..<3) == 0)
        #expect(inkCount(of: screen, columns: 0..<2, rows: 1..<3) == 0)
    }
}
