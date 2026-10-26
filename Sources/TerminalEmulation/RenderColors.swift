import GhosttyVt

/// The colors in force for one update: the defaults of the embedder, or the
/// colors a program set with OSC 4, 10, 11 and 12.
public struct RenderColors: Equatable, Sendable {
    public var background: TerminalColor
    public var foreground: TerminalColor
    /// `nil` when neither the embedder nor the program chose a cursor color.
    public var cursor: TerminalColor?
    /// The 256-color palette.
    public var palette: [TerminalColor]
}

extension TerminalColor {
    init(_ color: GhosttyColorRgb) {
        self.init(red: color.r, green: color.g, blue: color.b)
    }
}

extension TerminalColor {
    /// Resolves a style color, or returns `nil` for the default color.
    init?(_ color: GhosttyStyleColor, palette: [TerminalColor]) {
        switch color.tag {
        case GHOSTTY_STYLE_COLOR_RGB:
            self.init(color.value.rgb)
        case GHOSTTY_STYLE_COLOR_PALETTE:
            guard Int(color.value.palette) < palette.count else { return nil }
            self = palette[Int(color.value.palette)]
        default:
            return nil
        }
    }
}
