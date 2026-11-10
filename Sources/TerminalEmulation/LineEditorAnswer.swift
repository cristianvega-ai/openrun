/// Finds where a line editor, in its answer to a new terminal size, has erased
/// its lines.
///
/// After SIGWINCH, zsh and readline move the cursor up by the number of rows
/// that their lines took at the old width. They erase from there and draw the
/// lines again at the new width. That number is right only on a screen that
/// still has the old width, because the primary screen reflows its text when
/// it changes size. So a copy of the screen keeps the old width until the
/// erase, and takes the new width just after it. The editor's erase then
/// removes exactly its old lines, and nothing above them.
///
/// The answer also ends when the editor stops editing (`CSI ? 2004 l`, or
/// `OSC 133 ; C` of a shell that marks its prompt). The shell then runs a
/// command, and the command writes for the new size.
///
/// Give it the program's output in order, until it returns an end.
public struct LineEditorAnswer: Sendable {
    /// Where an answer ended.
    public struct End: Equatable, Sendable {
        /// The index in the output just after the answer.
        public var index: Int
        /// Whether the editor erased its lines there. It is false when the
        /// editor stopped editing.
        public var erasedLines: Bool
    }

    private static let editingEnd = Array("\u{1b}[?2004l".utf8)
    private static let lastRowErase = Array("\r\u{1b}[K".utf8)
    private static let rowAboveErases = [Array("\r\u{1b}[A\u{1b}[K".utf8), Array("\u{1b}[A\u{1b}[K".utf8)]

    private let editor: LineEditor
    /// The last bytes of the output, enough for the longest sequence. A
    /// sequence can start in an earlier piece of output.
    private var recentBytes: [UInt8] = []
    /// The bytes since readline's last erase of a row, or nil before its
    /// first erase. Readline erases its rows from the bottom up, so the
    /// answer ends only when a byte does not start another erase.
    private var bytesAfterErase: [UInt8]?
    /// zsh and a shell with prompt marks answer with the start of a prompt.
    private var promptScanner = ShellPromptScanner()

    public init(editor: LineEditor) {
        self.editor = editor
    }

    /// Where in `bytes` the answer ended, just after the editor's erase, so a
    /// copy of the screen takes the new width there. Nil when the answer has
    /// not ended yet.
    public mutating func end(in bytes: ArraySlice<UInt8>) -> End? {
        guard editor == .readline else {
            for hit in promptScanner.hits(in: bytes) {
                switch (hit.event, editor) {
                // fish turns bracketed paste off and on while it draws, so
                // only its mark of a command ends its editing.
                case (.editingEnd, .zsh), (.commandStart, _): return End(index: hit.index, erasedLines: false)
                case (.zshPromptStart, .zsh), (.markedPromptStart, .markedPrompt): return End(index: hit.index, erasedLines: true)
                default: continue
                }
            }
            return nil
        }
        for index in bytes.indices {
            let byte = bytes[index]
            if var after = bytesAfterErase {
                after.append(byte)
                if Self.rowAboveErases.contains(after) {
                    bytesAfterErase = []
                } else if Self.rowAboveErases.contains(where: { $0.starts(with: after) }) {
                    bytesAfterErase = after
                } else {
                    // These bytes came after the last erase. When some of
                    // them were in an earlier piece, the copy parsed them at
                    // the old width already, and they hold no text.
                    return End(index: max(bytes.startIndex, index + 1 - after.count), erasedLines: true)
                }
                continue
            }
            recentBytes.append(byte)
            if recentBytes.count > Self.editingEnd.count { recentBytes.removeFirst() }
            if endsRecentBytes(Self.editingEnd) { return End(index: index + 1, erasedLines: false) }
            if endsRecentBytes(Self.lastRowErase) { bytesAfterErase = [] }
        }
        return nil
    }

    private func endsRecentBytes(_ sequence: [UInt8]) -> Bool {
        recentBytes.count >= sequence.count && recentBytes.suffix(sequence.count).elementsEqual(sequence)
    }
}
