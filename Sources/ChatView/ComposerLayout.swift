import CoreGraphics

/// The places of the parts of the composer at a width: the note, the box
/// with its images, field and button, and the line of facts under it.
struct ComposerLayout: Equatable {
    static let maximumFieldHeight: CGFloat = 180
    static let padding = CGSize(width: 14, height: 11)
    static let buttonSide: CGFloat = 28
    static let noteHeight: CGFloat = 22

    var note: CGRect?
    /// The message that waits while the agent works.
    var held: CGRect?
    var box: CGRect
    /// The places in the box.
    var previews: CGRect?
    var field: CGRect
    var button: CGRect
    var footer: CGRect
    var height: CGFloat

    static func fieldWidth(forWidth width: CGFloat) -> CGFloat {
        max(40, ChatColumn.frame(inWidth: width).width - 2 * padding.width - buttonSide - 6)
    }

    /// - Parameter textHeight: The height of the text in the field. The
    ///   field grows with it up to a limit, and then scrolls.
    init(width: CGFloat, textHeight: CGFloat, lineHeight: CGFloat, hasNote: Bool, hasImages: Bool, heldHeight: CGFloat = 0) {
        let column = ChatColumn.frame(inWidth: width)
        let pad = Self.padding
        let fieldHeight = min(Self.maximumFieldHeight, max(lineHeight, textHeight))
        note = hasNote ? CGRect(x: column.x + 4, y: 0, width: column.width - 8, height: 18) : nil
        previews = hasImages ? CGRect(x: pad.width, y: pad.height, width: column.width - 2 * pad.width, height: ImagePreviewsView.height) : nil
        field = CGRect(x: pad.width, y: previews.map { $0.maxY + 8 } ?? pad.height, width: Self.fieldWidth(forWidth: width), height: fieldHeight)
        let top = hasNote ? Self.noteHeight : 0
        held = heldHeight > 0 ? CGRect(x: column.x, y: top, width: column.width, height: heldHeight) : nil
        box = CGRect(x: column.x, y: held.map { $0.maxY + 6 } ?? top, width: column.width, height: field.maxY + pad.height)
        button = CGRect(x: box.width - Self.buttonSide - 8, y: box.height - Self.buttonSide - 6, width: Self.buttonSide, height: Self.buttonSide)
        footer = CGRect(x: column.x + 2, y: box.maxY + 4, width: column.width - 4, height: ComposerFooterView.height)
        height = footer.maxY + 8
    }
}
