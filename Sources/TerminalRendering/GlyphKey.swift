/// What decides how a glyph looks: its text, its face, and the number of
/// cells that it covers. A wide character covers 2 cells and sits in the middle.
struct GlyphKey: Hashable {
    let text: String
    let face: FontFace
    let columns: Int

    /// The wave of the `curly` underline. It has no character, so its text is empty.
    static let curlyUnderline = GlyphKey(text: "", face: .regular, columns: 1)
}
