import AppKit

/// The pasteboard that the view copies to and pastes from. A test gives another
/// one, so it needs no real pasteboard.
@MainActor
protocol PasteboardAccess: AnyObject {
    /// The plain text on the pasteboard, or `nil` when it has none.
    func plainText() -> String?
    /// Replaces the contents with plain text. Plain text only, because a program reads text.
    func write(plainText: String)
}

/// The general pasteboard of macOS.
@MainActor
final class GeneralPasteboard: PasteboardAccess {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func plainText() -> String? {
        pasteboard.string(forType: .string)
    }

    func write(plainText: String) {
        pasteboard.clearContents()
        pasteboard.setString(plainText, forType: .string)
    }
}
