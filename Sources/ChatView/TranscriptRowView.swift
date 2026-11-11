import AppKit

/// The view of one row of the transcript. Each kind of row has a subclass.
///
/// The transcript view measures a row with `height(forWidth:)` and then
/// gives it a frame of that height.
@MainActor class TranscriptRowView: NSView {
    private(set) var row = TranscriptRow(key: "", kind: .activity)
    private(set) weak var context: TranscriptRowContext?

    override var isFlipped: Bool { true }

    /// Shows the row as it is now. A subclass shows its content and calls
    /// this first.
    func configure(_ row: TranscriptRow, context: TranscriptRowContext) {
        self.row = row
        self.context = context
    }

    /// The height of the content at `width`, without the space above.
    func height(forWidth width: CGFloat) -> CGFloat {
        0
    }
}
