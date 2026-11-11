import AppKit
import CoreText

/// A monospaced font in its four faces at one size and one backing scale, with
/// the cell that the regular face makes. SF Mono is the font unless the owner
/// names another one.
public final class FontSet {
    public let pointSize: CGFloat
    /// The number of pixels for each point of the screen that shows the view.
    public let scale: CGFloat
    /// The name that the owner gave, or `nil` for SF Mono. The font is SF Mono also
    /// when no installed monospaced font has this name.
    public let fontName: String?
    let metrics: CellMetrics
    private let faces: [CTFont]

    /// - Parameter fontName: The PostScript name or the family name of an installed monospaced font.
    public init(pointSize: CGFloat, scale: CGFloat, fontName: String? = nil) {
        self.pointSize = pointSize
        self.scale = scale
        self.fontName = fontName
        // The fonts have their size in pixels, so a glyph drawn at one pixel
        // for each bitmap pixel is sharp on a Retina screen.
        let pixels = pointSize * scale
        let named = fontName.flatMap { Self.monospacedFont(named: $0, size: pixels) }
        let regular = named ?? NSFont.monospacedSystemFont(ofSize: pixels, weight: .regular) as CTFont
        let bold = named.map { CTFontCreateCopyWithSymbolicTraits($0, pixels, nil, .traitBold, .traitBold) ?? $0 }
            ?? NSFont.monospacedSystemFont(ofSize: pixels, weight: .bold) as CTFont
        // SF Mono and most monospaced fonts have real italic faces, so nothing is slanted.
        let italic = CTFontCreateCopyWithSymbolicTraits(regular, pixels, nil, .traitItalic, .traitItalic) ?? regular
        let boldItalic = CTFontCreateCopyWithSymbolicTraits(bold, pixels, nil, .traitItalic, .traitItalic) ?? bold
        faces = [regular, bold, italic, boldItalic]
        metrics = CellMetrics(font: regular)
    }

    /// The width of a cell in pixels.
    public var cellWidth: Int { metrics.width }
    /// The height of a cell in pixels.
    public var cellHeight: Int { metrics.height }

    /// A font with this PostScript name or family name, when it is installed and
    /// monospaced. A proportional font would not fit the cells of the grid.
    private static func monospacedFont(named name: String, size: CGFloat) -> CTFont? {
        let font = NSFont(name: name, size: size)
            ?? NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
        guard let font = font as CTFont? else { return nil }
        if CTFontGetSymbolicTraits(font).contains(.traitMonoSpace) { return font }
        // Some monospaced fonts do not set the trait, so the widths of narrow and wide letters tell.
        var characters: [UniChar] = [0x69, 0x4D, 0x57], glyphs = [CGGlyph](repeating: 0, count: 3)
        var advances = [CGSize](repeating: .zero, count: 3)
        guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 3) else { return nil }
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, 3)
        return Set(advances.map { ($0.width * 64).rounded() }).count == 1 ? font : nil
    }

    func font(for face: FontFace) -> CTFont {
        faces[face.rawValue]
    }
}
