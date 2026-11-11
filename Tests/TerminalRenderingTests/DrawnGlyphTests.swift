import Testing
import TerminalEmulation
@testable import TerminalRendering

@Suite struct DrawnGlyphTests {
    private func bitmap(_ text: String, columns: Int = 1) -> GlyphRasterizer.Bitmap? {
        DrawnGlyph.bitmap(for: GlyphKey(text: text, face: .bold, columns: columns), cellWidth: 16, cellHeight: 31)
    }

    @Test func aDrawnCharacterFillsItsCellsAndOtherTextGoesToTheFont() throws {
        let line = try #require(bitmap("─"))
        #expect(line.width == 16 && line.height == 31 && line.horizontalOffset == 0 && line.verticalOffset == 0)
        #expect(try #require(bitmap("─", columns: 2)).width == 32)
        #expect(bitmap("A") == nil && bitmap("─\u{301}") == nil && bitmap("") == nil)
    }

    @Test func theRasterizerUsesTheDrawingInPlaceOfTheFont() throws {
        let drawn = try #require(GlyphRasterizer(fonts: testFonts).bitmap(for: GlyphKey(text: "│", face: .regular, columns: 1)))
        #expect(drawn.width == testFonts.cellWidth && drawn.height == testFonts.cellHeight && drawn.verticalOffset == 0)
    }

    @Test func aCornerHasNoNotchAndADoubleJointKeepsItsGapOpen() throws {
        let corner = try #require(bitmap("┌")), joint = try #require(bitmap("╬"))
        func coverage(_ bitmap: GlyphRasterizer.Bitmap, _ column: Int, _ row: Int) -> UInt8 { bitmap.pixels[row * 16 + column] }
        // The light lines are 2 pixels in the middle: columns 7 and 8, rows 14 and 15.
        #expect(coverage(corner, 7, 14) == 255 && coverage(corner, 6, 14) == 0 && coverage(corner, 7, 13) == 0)
        #expect(coverage(joint, 7, 15) == 0 && coverage(joint, 7, 0) == 0)
        #expect(coverage(joint, 5, 0) == 255 && coverage(joint, 0, 12) == 255)
    }

    @Test func theLinesOfAFrameJoinAcrossRowsAndColumnsOnTheScreen() throws {
        let screen = try renderScreen("\u{1B}[?25l┌─┐\r\n└─┘", columns: 4, rows: 2)
        let (width, height) = (testFonts.cellWidth, testFonts.cellHeight)
        let foreground = screen.theme.foreground
        // The middle of the vertical line at the bottom of the first row and at the top of the second.
        #expect(pixel(of: screen.target, horizontalPosition: width / 2 - 1, verticalPosition: height - 1) == foreground)
        #expect(pixel(of: screen.target, row: 1, horizontalPosition: width / 2 - 1, verticalPosition: 0) == foreground)
        // The horizontal line at the right edge of the corner and at the left edge of its neighbor.
        #expect(pixel(of: screen.target, horizontalPosition: width - 1, verticalPosition: height / 2 - 1) == foreground)
        #expect(pixel(of: screen.target, column: 1, horizontalPosition: 0, verticalPosition: height / 2 - 1) == foreground)
        #expect(pixel(of: screen.target, column: 2, horizontalPosition: width - 1, verticalPosition: height / 2 - 1) != foreground)
    }
}
