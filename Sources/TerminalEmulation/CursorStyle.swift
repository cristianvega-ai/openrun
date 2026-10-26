import GhosttyVt

/// The shapes a program can ask for with DECSCUSR.
public enum CursorStyle: Equatable, Sendable {
    case block, hollowBlock, bar, underline

    init(_ style: GhosttyRenderStateCursorVisualStyle) {
        switch style {
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR: self = .bar
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE: self = .underline
        case GHOSTTY_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW: self = .hollowBlock
        default: self = .block
        }
    }
}
