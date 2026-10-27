import GhosttyVt

/// The direction in which a drag of the selection asks the viewport to scroll.
public enum SelectionAutoscroll: Equatable, Sendable {
    case none, up, down

    init(_ direction: GhosttySelectionGestureAutoscroll) {
        switch direction {
        case GHOSTTY_SELECTION_GESTURE_AUTOSCROLL_UP: self = .up
        case GHOSTTY_SELECTION_GESTURE_AUTOSCROLL_DOWN: self = .down
        default: self = .none
        }
    }
}
