import AppKit
import TerminalEmulation

/// The cursor of the mouse for a pointer shape that the program asked for with OSC 22.
enum PointerShapeCursor {
    static func cursor(for shape: PointerShape) -> NSCursor {
        switch shape {
        case .text, .other: .iBeam
        case .arrow: .arrow
        case .pointingHand: .pointingHand
        case .crosshair: .crosshair
        case .notAllowed: .operationNotAllowed
        case .openHand: .openHand
        case .closedHand: .closedHand
        case .resizeLeftRight: .resizeLeftRight
        case .resizeUpDown: .resizeUpDown
        }
    }
}
