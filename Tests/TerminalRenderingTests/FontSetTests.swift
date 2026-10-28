import CoreText
import Testing
@testable import TerminalRendering

@Suite struct FontSetTests {
    @Test func thirteenPointsAtScaleTwoMakeACellOf16By31Pixels() {
        let fonts = FontSet(pointSize: 13, scale: 2)
        #expect(fonts.cellWidth == 16)
        #expect(fonts.cellHeight == 31)
    }

    @Test func everyFaceIsSFMonoAndItalicFacesSlant() {
        let fonts = FontSet(pointSize: 13, scale: 2)
        let names = FontFace.allCases.map { CTFontCopyPostScriptName(fonts.font(for: $0)) as String }
        #expect(names.allSatisfy { $0.hasPrefix(".AppleSystemUIFontMonospaced") })
        #expect(Set(names).count == 4)
        #expect(names[FontFace.italic.rawValue].hasSuffix("Italic"))
    }

    @Test func linesLieInsideTheCell() {
        let metrics = FontSet(pointSize: 13, scale: 2).metrics
        #expect(metrics.strikethroughPosition < metrics.baseline)
        #expect(metrics.baseline < metrics.underlinePosition)
        #expect(metrics.underlinePosition + metrics.underlineThickness <= metrics.height)
    }
}

@Suite struct GlyphRasterizerTests {
    private let fonts = FontSet(pointSize: 13, scale: 2)

    private func bitmap(_ text: String, _ face: FontFace = .regular, columns: Int = 1) -> GlyphRasterizer.Bitmap? {
        GlyphRasterizer(fonts: fonts).bitmap(for: GlyphKey(text: text, face: face, columns: columns))
    }

    @Test func aLetterStandsOnTheBaselineOfTheCell() throws {
        let letter = try #require(bitmap("A"))
        #expect(letter.pixels.contains { $0 > 200 })
        let bottom = letter.verticalOffset + letter.height - GlyphRasterizer.padding
        #expect(abs(bottom - fonts.metrics.baseline) <= 1)
    }

    @Test func aSpaceDrawsNothing() {
        #expect(bitmap(" ") == nil)
    }

    @Test func aWideCharacterSitsInsideItsTwoCells() throws {
        let wide = try #require(bitmap("日", columns: 2))
        #expect(wide.horizontalOffset + GlyphRasterizer.padding >= 0)
        #expect(wide.horizontalOffset + wide.width - GlyphRasterizer.padding <= 2 * fonts.cellWidth)
    }

    @Test func anEmojiFitsInItsCellsAndIsNeverEnlarged() throws {
        let padding = GlyphRasterizer.padding
        for columns in [1, 2] {
            let emoji = try #require(bitmap("🙂", columns: columns))
            #expect(emoji.isColor)
            #expect(emoji.horizontalOffset + padding >= 0)
            #expect(emoji.horizontalOffset + emoji.width - padding <= columns * fonts.cellWidth)
            // The bitmap rounds its edges outward, by less than one pixel each.
            #expect(emoji.verticalOffset + padding >= -1)
            #expect(emoji.verticalOffset + emoji.height - padding <= fonts.cellHeight + 1)
        }
        #expect(try #require(bitmap("🙂", columns: 4)).width == #require(bitmap("🙂", columns: 2)).width)
    }

    @Test func theBoldFaceCoversMorePixels() throws {
        let regular = try #require(bitmap("M")).pixels.reduce(0) { $0 + Int($1) }
        let bold = try #require(bitmap("M", .bold)).pixels.reduce(0) { $0 + Int($1) }
        #expect(bold > regular)
    }
}
