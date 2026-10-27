import AppKit
import TerminalEmulation

/// Decides what a mouse event does. It goes to the program as a report when the
/// program asked for reports. Shift gives the mouse to the selection.
@MainActor
final class PointerInput {
    let reporter: MouseReporter
    /// The buttons whose press went to the program. Their motion and release go there too.
    private var reportedButtons: Set<MouseEvent.Button> = []

    init(terminal: Terminal) throws {
        reporter = try MouseReporter(terminal: terminal)
    }

    /// AppKit counts the buttons from 0: left, right, middle, back and forward.
    static func button(forNumber number: Int) -> MouseEvent.Button? {
        [0: .left, 1: .right, 2: .middle, 3: .back, 4: .forward][number]
    }

    /// - Returns: The bytes for the program, which can be empty when the encoder drops the
    ///   event, or `nil` when the event is not for the program.
    func bytes(
        _ action: MouseEvent.Action, button: MouseEvent.Button?, modifiers: NSEvent.ModifierFlags, at point: CGPoint, in location: PointerLocation
    ) -> [UInt8]? {
        switch action {
        case .press:
            guard reporter.isActive, !modifiers.contains(.shift) else { return nil }
            if let button { reportedButtons.insert(button) }
        case .motion:
            // A motion with no button is for the program if the program asked, and the user did not press Shift.
            if let button { guard reportedButtons.contains(button) else { return nil } } else if modifiers.contains(.shift) { return nil }
        case .release:
            guard let button, reportedButtons.remove(button) != nil else { return nil }
        }
        return reporter.bytes(action, button: button, modifiers: ModifierReader.modifiers(of: modifiers), at: point, in: location)
    }
}
