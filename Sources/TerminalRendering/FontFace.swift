import TerminalEmulation

/// The four faces of the font that a terminal draws with.
enum FontFace: Int, CaseIterable, Sendable {
    case regular, bold, italic, boldItalic

    init(style: CellStyle) {
        switch (style.isBold, style.isItalic) {
        case (true, true): self = .boldItalic
        case (true, false): self = .bold
        case (false, true): self = .italic
        case (false, false): self = .regular
        }
    }
}
