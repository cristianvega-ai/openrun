import GhosttyVt

/// How many columns the character of a cell takes.
public enum CellWidth: Equatable, Sendable {
    case narrow, wide
    /// The second column of a wide character, and the last column of a
    /// row that a wide character did not fit into. Nothing to draw.
    case wideTail, wideHead

    init(_ wide: GhosttyCellWide) {
        switch wide {
        case GHOSTTY_CELL_WIDE_WIDE: self = .wide
        case GHOSTTY_CELL_WIDE_SPACER_TAIL: self = .wideTail
        case GHOSTTY_CELL_WIDE_SPACER_HEAD: self = .wideHead
        default: self = .narrow
        }
    }
}
