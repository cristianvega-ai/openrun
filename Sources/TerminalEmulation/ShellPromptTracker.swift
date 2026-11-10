import GhosttyVt

/// The first row of the prompt that a shell draws, found in the output that a
/// terminal parses (see `ShellPromptScanner`). The session process writes the
/// output of its program through it.
///
/// The row is a tracked position, so it stays right as the screen scrolls
/// and reflows. The end of editing clears it. Only the session process tracks
/// the prompt, and it tells each client what to keep of it.
public final class ShellPromptTracker {
    /// The prompt at the cursor.
    public struct Prompt: Sendable, Equatable {
        /// The line editor that draws the prompt again after a new size.
        public var editor: LineEditor
        /// The rows from the first row of the prompt down to the cursor.
        public var rowsAboveCursor: Int
    }

    private let terminal: Terminal
    private var scanner = ShellPromptScanner()
    private var start: GhosttyTrackedGridRef?
    private var editor: LineEditor?

    public init(terminal: Terminal) {
        self.terminal = terminal
    }

    deinit {
        ghostty_tracked_grid_ref_free(start)
    }

    /// The prompt at the cursor, or nil when no shell edits a line there.
    /// zsh and fish edit a line only while bracketed paste is on, and other
    /// programs can write the bytes of a prompt too.
    public var prompt: Prompt? {
        guard let editor, let start, !terminal.isAlternateScreenActive, terminal.isModeEnabled(.bracketedPaste) else { return nil }
        var point = GhosttyPointCoordinate()
        guard ghostty_tracked_grid_ref_point(start, GHOSTTY_POINT_TAG_ACTIVE, &point) == GHOSTTY_SUCCESS else { return nil }
        let rows = Int(terminal.cursorPosition.row) - Int(point.y)
        return rows >= 0 ? Prompt(editor: editor, rowsAboveCursor: rows) : nil
    }

    /// Parses output, and notes each start of a prompt in it.
    public func write(_ bytes: ArraySlice<UInt8>) {
        var written = bytes.startIndex
        for hit in scanner.hits(in: bytes) {
            terminal.write(bytes[written..<hit.index])
            written = hit.index
            switch hit.event {
            case .zshPromptStart: noteStart(editor: .zsh, rowsAboveCursor: 0)
            case .markedPromptStart: noteStart(editor: .markedPrompt, rowsAboveCursor: 0)
            // fish turns bracketed paste off and on while it draws.
            case .editingEnd: if editor == .zsh { editor = nil }
            case .commandStart: editor = nil
            }
        }
        terminal.write(bytes[written...])
    }

    /// zsh moves to the first column before it starts its prompt. Bytes like
    /// its start elsewhere are not a prompt.
    private func noteStart(editor: LineEditor, rowsAboveCursor rows: Int) {
        let cursor = terminal.cursorPosition
        self.editor = nil
        guard !terminal.isAlternateScreenActive, editor != .zsh || rows > 0 || cursor.column == 0, Int(cursor.row) >= rows else { return }
        var point = GhosttyPoint()
        point.tag = GHOSTTY_POINT_TAG_ACTIVE
        point.value.coordinate = GhosttyPointCoordinate(x: 0, y: UInt32(Int(cursor.row) - rows))
        let result = if let start { ghostty_tracked_grid_ref_set(start, terminal.handle, point) } else { ghostty_terminal_grid_ref_track(terminal.handle, point, &start) }
        if result == GHOSTTY_SUCCESS { self.editor = editor }
    }
}
