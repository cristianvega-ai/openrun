import GhosttyVt

/// Encodes mouse events with the tracking mode and format the program set.
public final class MouseEncoder {
    private let encoder: GhosttyMouseEncoder
    private let event: GhosttyMouseEvent

    public init() throws {
        var encoder: GhosttyMouseEncoder?
        var event: GhosttyMouseEvent?
        try TerminalEmulationError.check(ghostty_mouse_encoder_new(nil, &encoder), from: "ghostty_mouse_encoder_new")
        guard ghostty_mouse_event_new(nil, &event) == GHOSTTY_SUCCESS, let encoder, let event else {
            ghostty_mouse_encoder_free(encoder)
            throw TerminalEmulationError.invalidValue(in: "MouseEncoder.init")
        }
        self.encoder = encoder
        self.event = event
        // The program hears a motion only when the pointer enters a new cell.
        var deduplicate = true
        ghostty_mouse_encoder_setopt(encoder, GHOSTTY_MOUSE_ENCODER_OPT_TRACK_LAST_CELL, &deduplicate)
    }

    deinit {
        ghostty_mouse_event_free(event)
        ghostty_mouse_encoder_free(encoder)
    }

    /// Reads the modes of the terminal. Call it only when they or the cell
    /// size change, because it forgets the last cell.
    public func update(from terminal: Terminal, cellWidth: UInt32, cellHeight: UInt32, anyButtonPressed: Bool) {
        ghostty_mouse_encoder_setopt_from_terminal(encoder, terminal.handle)
        let grid = terminal.size
        var size = GhosttyMouseEncoderSize(
            size: MemoryLayout<GhosttyMouseEncoderSize>.size,
            screen_width: UInt32(grid.columns) * cellWidth, screen_height: UInt32(grid.rows) * cellHeight,
            cell_width: cellWidth, cell_height: cellHeight,
            padding_top: 0, padding_bottom: 0, padding_right: 0, padding_left: 0)
        ghostty_mouse_encoder_setopt(encoder, GHOSTTY_MOUSE_ENCODER_OPT_SIZE, &size)
        var pressed = anyButtonPressed
        ghostty_mouse_encoder_setopt(encoder, GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED, &pressed)
    }

    public func encode(_ mouse: MouseEvent) throws -> [UInt8] {
        ghostty_mouse_event_set_action(event, GhosttyMouseAction(rawValue: mouse.action.rawValue))
        switch mouse.button {
        case let button?: ghostty_mouse_event_set_button(event, GhosttyMouseButton(rawValue: button.rawValue))
        case nil: ghostty_mouse_event_clear_button(event)
        }
        ghostty_mouse_event_set_mods(event, mouse.modifiers.rawValue)
        ghostty_mouse_event_set_position(event, GhosttyMousePosition(x: mouse.x, y: mouse.y))
        var output = [UInt8](repeating: 0, count: 64)
        var written = 0
        let result = output.withUnsafeMutableBytes {
            ghostty_mouse_encoder_encode(encoder, event, $0.baseAddress?.assumingMemoryBound(to: CChar.self), $0.count, &written)
        }
        try TerminalEmulationError.check(result, from: "ghostty_mouse_encoder_encode")
        return Array(output.prefix(written))
    }
}
