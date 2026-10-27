import CoreText

/// The size of one cell and the places of the lines in it. All values are
/// whole pixels of the drawable, so the cells fit together with no gap, and
/// the lines are sharp. The vertical values count from the top of the cell.
struct CellMetrics: Equatable, Sendable {
    let width: Int
    let height: Int
    let baseline: Int
    let underlinePosition: Int
    let underlineThickness: Int
    let strikethroughPosition: Int

    init(font: CTFont) {
        // A monospaced font gives every character the width of the "M".
        var character = UniChar(0x4D), glyph = CGGlyph(0), advance = CGSize.zero
        CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        let ascent = CTFontGetAscent(font)
        let leading = CTFontGetLeading(font)
        width = Int(advance.width.rounded())
        height = Int((ascent + CTFontGetDescent(font) + leading).rounded(.up))
        baseline = Int((ascent + leading / 2).rounded())
        underlineThickness = max(1, Int(CTFontGetUnderlineThickness(font).rounded()))
        // CoreText gives the position below the baseline as a negative number.
        underlinePosition = baseline + max(1, Int((-CTFontGetUnderlinePosition(font)).rounded()))
        strikethroughPosition = baseline - Int((CTFontGetXHeight(font) / 2).rounded())
    }
}
