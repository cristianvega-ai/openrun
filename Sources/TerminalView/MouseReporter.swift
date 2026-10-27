import CoreGraphics
import TerminalEmulation
import os

/// Makes the mouse reports that a program asked for, with the mouse encoder
/// of libghostty-vt.
@MainActor
final class MouseReporter {
    /// What the encoder read from the terminal and the view.
    private struct Configuration: Equatable {
        let modes: [Bool], cellWidth: UInt32, cellHeight: UInt32, gridSize: TerminalSize
    }

    private static let wheelButtons: Set<MouseEvent.Button> = [.wheelUp, .wheelDown, .wheelLeft, .wheelRight]
    private let terminal: Terminal
    private let encoder: MouseEncoder
    private var configuration: Configuration?
    private var pressedButtons: Set<MouseEvent.Button> = []
    private let logger = Logger(subsystem: "ai.cristianvega.openrun", category: "MouseReporter")

    init(terminal: Terminal) throws {
        self.terminal = terminal
        encoder = try MouseEncoder()
    }

    /// Whether the program asked for mouse reports.
    var isActive: Bool { terminal.isMouseTrackingActive }

    /// The bytes for a mouse event. They are empty when the program does not want the event.
    func bytes(
        _ action: MouseEvent.Action, button: MouseEvent.Button?, modifiers: KeyModifiers, at point: CGPoint, in location: PointerLocation
    ) -> [UInt8] {
        guard isActive else { return [] }
        // A wheel turn is a press with no release, and its button does not stay down.
        if let button, !Self.wheelButtons.contains(button) {
            if action == .press { pressedButtons.insert(button) } else if action == .release { pressedButtons.remove(button) }
        }
        read(location)
        encoder.setAnyButtonPressed(!pressedButtons.isEmpty)
        let pixel = location.pixel(of: point)
        do {
            return try encoder.encode(MouseEvent(action: action, button: button, modifiers: modifiers, x: pixel.x, y: pixel.y))
        } catch {
            logger.error("A mouse report failed: \(String(describing: error), privacy: .private)")
            return []
        }
    }

    /// Reads the encoder again only when the modes or the geometry change. A read forgets
    /// the last cell, and the encoder then reports a motion in the same cell a second time.
    private func read(_ location: PointerLocation) {
        let new = Configuration(
            modes: TerminalMode.mouseModes.map(terminal.isModeEnabled),
            cellWidth: UInt32((location.cellSize.width * location.scale).rounded()),
            cellHeight: UInt32((location.cellSize.height * location.scale).rounded()), gridSize: location.gridSize)
        guard new != configuration else { return }
        configuration = new
        encoder.update(from: terminal, cellWidth: new.cellWidth, cellHeight: new.cellHeight, anyButtonPressed: !pressedButtons.isEmpty)
    }
}
