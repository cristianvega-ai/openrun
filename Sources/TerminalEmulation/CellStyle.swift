import GhosttyVt

/// The text attributes of a cell, apart from its colors.
public struct CellStyle: Equatable, Hashable, Sendable {
    public var isBold = false
    public var isItalic = false
    public var isFaint = false
    public var isBlinking = false
    public var isInverse = false
    public var isInvisible = false
    public var isStruckThrough = false
    public var isOverlined = false
    public var underline: UnderlineStyle = .none

    public init() {}

    init(_ style: GhosttyStyle) {
        isBold = style.bold
        isItalic = style.italic
        isFaint = style.faint
        isBlinking = style.blink
        isInverse = style.inverse
        isInvisible = style.invisible
        isStruckThrough = style.strikethrough
        isOverlined = style.overline
        underline = UnderlineStyle(rawValue: style.underline) ?? .none
    }
}
