import GhosttyVt

/// Turns presses of the pointer into a selection with the rules of
/// libghostty-vt: quick clicks select a word, then a line. The result
/// becomes the selection of the terminal. A single press selects nothing,
/// so the view clears the old selection itself.
public final class SelectionGesture {
    // The gesture tracks cells of the terminal, so it keeps the terminal
    // alive and frees its cells before the terminal goes.
    private let terminal: Terminal
    private let gesture: GhosttySelectionGesture
    private let pressEvent: GhosttySelectionGestureEvent
    private let dragEvent: GhosttySelectionGestureEvent
    private let releaseEvent: GhosttySelectionGestureEvent
    private let tickEvent: GhosttySelectionGestureEvent

    public init(for terminal: Terminal) throws {
        var gesture: GhosttySelectionGesture?
        var press: GhosttySelectionGestureEvent?
        var drag: GhosttySelectionGestureEvent?
        var release: GhosttySelectionGestureEvent?
        var tick: GhosttySelectionGestureEvent?
        guard ghostty_selection_gesture_new(nil, &gesture) == GHOSTTY_SUCCESS,
              ghostty_selection_gesture_event_new(nil, &press, GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_PRESS) == GHOSTTY_SUCCESS,
              ghostty_selection_gesture_event_new(nil, &drag, GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_DRAG) == GHOSTTY_SUCCESS,
              ghostty_selection_gesture_event_new(nil, &release, GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_RELEASE) == GHOSTTY_SUCCESS,
              ghostty_selection_gesture_event_new(nil, &tick, GHOSTTY_SELECTION_GESTURE_EVENT_TYPE_AUTOSCROLL_TICK) == GHOSTTY_SUCCESS,
              let gesture, let press, let drag, let release, let tick
        else {
            ghostty_selection_gesture_event_free(press)
            ghostty_selection_gesture_event_free(drag)
            ghostty_selection_gesture_event_free(release)
            ghostty_selection_gesture_event_free(tick)
            ghostty_selection_gesture_free(gesture, nil)
            throw TerminalEmulationError.invalidValue(in: "SelectionGesture.init")
        }
        (self.terminal, self.gesture, pressEvent, dragEvent, releaseEvent, tickEvent) = (terminal, gesture, press, drag, release, tick)
    }

    deinit {
        ghostty_selection_gesture_event_free(pressEvent)
        ghostty_selection_gesture_event_free(dragEvent)
        ghostty_selection_gesture_event_free(releaseEvent)
        ghostty_selection_gesture_event_free(tickEvent)
        ghostty_selection_gesture_free(gesture, terminal.handle)
    }

    /// A press of the primary button. The time is from a steady clock. The
    /// repeat interval is the longest time between the clicks of a double
    /// click, which the view takes from the system.
    public func press(at cell: ViewportCell, pixel: (horizontalPosition: Double, verticalPosition: Double), timeInNanoseconds: UInt64, repeatIntervalInNanoseconds: UInt64) throws {
        var reference = try terminal.gridReference(at: cell)
        var position = GhosttySurfacePosition(x: pixel.horizontalPosition, y: pixel.verticalPosition)
        var time = timeInNanoseconds
        var interval = repeatIntervalInNanoseconds
        var distance = 8.0  // pixels that the pointer may move between clicks
        _ = ghostty_selection_gesture_event_set(pressEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &reference)
        _ = ghostty_selection_gesture_event_set(pressEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION, &position)
        _ = ghostty_selection_gesture_event_set(pressEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_TIME_NS, &time)
        _ = ghostty_selection_gesture_event_set(pressEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_INTERVAL_NS, &interval)
        _ = ghostty_selection_gesture_event_set(pressEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REPEAT_DISTANCE, &distance)
        try apply(pressEvent)
    }

    /// The pointer moves with the button down. The selection grows from the
    /// press to `cell`. The geometry lets libghostty-vt choose the side of
    /// the cell where the selection ends.
    public func drag(to cell: ViewportCell, pixel: (horizontalPosition: Double, verticalPosition: Double), cellWidth: UInt32, screenHeight: UInt32) throws {
        var reference = try terminal.gridReference(at: cell)
        var position = GhosttySurfacePosition(x: pixel.horizontalPosition, y: pixel.verticalPosition)
        var geometry = GhosttySelectionGestureGeometry(
            columns: UInt32(terminal.size.columns), cell_width: cellWidth, padding_left: 0, screen_height: screenHeight)
        _ = ghostty_selection_gesture_event_set(dragEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &reference)
        _ = ghostty_selection_gesture_event_set(dragEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION, &position)
        _ = ghostty_selection_gesture_event_set(dragEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_GEOMETRY, &geometry)
        try apply(dragEvent)
    }

    /// A step of the autoscroll. The viewport scrolls one row in the direction of
    /// `autoscroll`, and the selection grows to the cell now under the pointer.
    /// Call it from a timer while `autoscroll` is not `.none`.
    public func autoscrollTick(at cell: ViewportCell, pixel: (horizontalPosition: Double, verticalPosition: Double), cellWidth: UInt32, screenHeight: UInt32) throws {
        var viewport = GhosttyPointCoordinate(x: cell.column, y: cell.row)
        var position = GhosttySurfacePosition(x: pixel.horizontalPosition, y: pixel.verticalPosition)
        var geometry = GhosttySelectionGestureGeometry(
            columns: UInt32(terminal.size.columns), cell_width: cellWidth, padding_left: 0, screen_height: screenHeight)
        _ = ghostty_selection_gesture_event_set(tickEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_VIEWPORT, &viewport)
        _ = ghostty_selection_gesture_event_set(tickEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_POSITION, &position)
        _ = ghostty_selection_gesture_event_set(tickEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_GEOMETRY, &geometry)
        try apply(tickEvent)
    }

    /// Which way a drag asks the viewport to scroll. A drag at the top edge of the grid or above it
    /// asks for up, and a drag at the bottom edge or below it asks for down.
    public var autoscroll: SelectionAutoscroll {
        var direction = GHOSTTY_SELECTION_GESTURE_AUTOSCROLL_NONE
        _ = ghostty_selection_gesture_get(gesture, terminal.handle, GHOSTTY_SELECTION_GESTURE_DATA_AUTOSCROLL, &direction)
        return SelectionAutoscroll(direction)
    }

    public func release(at cell: ViewportCell) throws {
        var reference = try terminal.gridReference(at: cell)
        _ = ghostty_selection_gesture_event_set(releaseEvent, GHOSTTY_SELECTION_GESTURE_EVENT_OPT_REF, &reference)
        try apply(releaseEvent)
    }

    /// The clicks of the current press: 1, 2 or 3. It is 0 without a press.
    public var clickCount: Int {
        var count: UInt8 = 0
        _ = ghostty_selection_gesture_get(gesture, terminal.handle, GHOSTTY_SELECTION_GESTURE_DATA_CLICK_COUNT, &count)
        return Int(count)
    }

    /// Applies an event and installs the selection that it makes.
    private func apply(_ event: GhosttySelectionGestureEvent) throws {
        var selection = GhosttySelection()
        selection.size = MemoryLayout<GhosttySelection>.size
        let result = ghostty_selection_gesture_event(gesture, terminal.handle, event, &selection)
        if result == GHOSTTY_NO_VALUE { return }
        try TerminalEmulationError.check(result, from: "ghostty_selection_gesture_event")
        try TerminalEmulationError.check(ghostty_terminal_set(terminal.handle, GHOSTTY_TERMINAL_OPT_SELECTION, &selection), from: "ghostty_terminal_set")
    }
}
