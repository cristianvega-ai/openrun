import CoreGraphics

/// The column that the text of the chat stands in.
///
/// Prose is easiest to read at a limited measure, so on a wide pane the
/// column keeps its width and stands in the middle, as in a book.
enum ChatColumn {
    static let maximumWidth: CGFloat = 720
    static let minimumMargin: CGFloat = 20

    /// The left edge and the width of the column in a row of `width`.
    static func frame(inWidth width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let margin = max(minimumMargin, ((width - maximumWidth) / 2).rounded(.down))
        return (margin, max(0, width - 2 * margin))
    }
}
