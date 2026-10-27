import AppKit
import CoreText

/// SF Mono in its four faces at one size and one backing scale, with the cell
/// that the regular face makes.
public final class FontSet {
    public let pointSize: CGFloat
    /// The number of pixels for each point of the screen that shows the view.
    public let scale: CGFloat
    let metrics: CellMetrics
    private let faces: [CTFont]

    public init(pointSize: CGFloat, scale: CGFloat) {
        self.pointSize = pointSize
        self.scale = scale
        // The fonts have their size in pixels, so a glyph drawn at one pixel
        // for each bitmap pixel is sharp on a Retina screen.
        let pixels = pointSize * scale
        let regular = NSFont.monospacedSystemFont(ofSize: pixels, weight: .regular) as CTFont
        let bold = NSFont.monospacedSystemFont(ofSize: pixels, weight: .bold) as CTFont
        // The system has real italic faces of SF Mono, so nothing is slanted.
        let italic = CTFontCreateCopyWithSymbolicTraits(regular, pixels, nil, .traitItalic, .traitItalic) ?? regular
        let boldItalic = CTFontCreateCopyWithSymbolicTraits(bold, pixels, nil, .traitItalic, .traitItalic) ?? bold
        faces = [regular, bold, italic, boldItalic]
        metrics = CellMetrics(font: regular)
    }

    /// The width of a cell in pixels.
    public var cellWidth: Int { metrics.width }
    /// The height of a cell in pixels.
    public var cellHeight: Int { metrics.height }

    func font(for face: FontFace) -> CTFont {
        faces[face.rawValue]
    }
}
