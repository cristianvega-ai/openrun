import AppKit
import Metal
import TerminalEmulation
@testable import TerminalRendering
import TerminalTheme
import Testing
@testable import TerminalView

@MainActor @Suite struct ViewportOfViewTests {
    @Test func hiddenGlyphsCannotFillTheAtlasBeforeAVisibleGlyph() throws {
        _ = NSApplication.shared
        let device = try #require(MTLCreateSystemDefaultDevice())
        let fonts = FontSet(pointSize: 36, scale: 2)
        let theme = TerminalTheme.graphite(for: .light)
        let visible = TerminalSize(columns: 4, rows: 2)
        let hidden = "一二三四五六七八九十百千万上下左右天地山水火木金土日月星辰春夏秋冬"

        func pixels(columns: UInt16, output: String) throws -> [UInt8] {
            let terminal = try Terminal(size: TerminalSize(columns: columns, rows: 2), scrollbackLimit: 0)
            terminal.write("\u{1B}[?25l" + output)
            let renderer = try TerminalRenderer(device: device, fonts: fonts, selectionColor: theme.selection,
                                                atlasSide: 128, atlasMaximumSide: 128)
            let view = try TerminalView(terminal: terminal, clock: SystemInputClock(), renderer: renderer)
            let size = renderer.pixelSize(for: visible)
            let target = try OffscreenTarget(device: device, width: size.width, height: size.height)
            #expect(try view.drawFrame(into: target))
            _ = target.pixel(horizontalPosition: 0, verticalPosition: 0)
            var result = [UInt8](repeating: 0, count: size.width * size.height * 4)
            target.texture.getBytes(&result, bytesPerRow: size.width * 4,
                                    from: MTLRegionMake2D(0, 0, size.width, size.height), mipmapLevel: 0)
            return result
        }

        let actual = try pixels(columns: 120, output: "\u{1B}[1;11H" + hidden + "\u{1B}[2;1HA")
        let reference = try pixels(columns: 4, output: "\u{1B}[2;1HA")
        let blank = try pixels(columns: 4, output: "")
        let referenceShowsGlyph = reference != blank
        let actualMatchesReference = actual == reference
        #expect(referenceShowsGlyph)
        #expect(actualMatchesReference, "Hidden glyphs must not prevent a visible glyph.")
    }
}
