import GhosttyVt

/// A pointer shape from OSC 22, reduced to the shapes that macOS has.
public enum PointerShape: Equatable, Sendable {
    case text, arrow, pointingHand, crosshair, notAllowed, openHand, closedHand
    case resizeLeftRight, resizeUpDown, other

    init(_ shape: GhosttyMouseShape) {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_TEXT, GHOSTTY_MOUSE_SHAPE_VERTICAL_TEXT: self = .text
        case GHOSTTY_MOUSE_SHAPE_DEFAULT: self = .arrow
        case GHOSTTY_MOUSE_SHAPE_POINTER: self = .pointingHand
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR, GHOSTTY_MOUSE_SHAPE_CELL: self = .crosshair
        case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED, GHOSTTY_MOUSE_SHAPE_NO_DROP: self = .notAllowed
        case GHOSTTY_MOUSE_SHAPE_GRAB: self = .openHand
        case GHOSTTY_MOUSE_SHAPE_GRABBING: self = .closedHand
        case GHOSTTY_MOUSE_SHAPE_COL_RESIZE, GHOSTTY_MOUSE_SHAPE_EW_RESIZE: self = .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_ROW_RESIZE, GHOSTTY_MOUSE_SHAPE_NS_RESIZE: self = .resizeUpDown
        default: self = .other
        }
    }
}

extension Terminal {
    /// The pointer shape that the program asked for with OSC 22. It starts
    /// as `.text`.
    public var pointerShape: PointerShape {
        var shape = GHOSTTY_MOUSE_SHAPE_TEXT
        _ = ghostty_terminal_get(handle, GHOSTTY_TERMINAL_DATA_MOUSE_SHAPE, &shape)
        return PointerShape(shape)
    }
}
