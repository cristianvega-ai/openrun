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
