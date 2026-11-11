import AppKit

/// A question that belongs to one session pane. It shows as a sheet on the window of the pane.
enum UserQuestion: Equatable, Sendable {
    case unsafePaste
    case unsafeInsertion
    case openLink(String)
    case connectionFailure(String)

    var words: (title: String, message: String, buttons: [String]) {
        switch self {
        case .unsafePaste:
            ("Paste multiple lines?", "This paste can run commands because the program does not protect pasted text.", ["Paste", "Cancel"])
        case .unsafeInsertion:
            ("Insert multiple lines?", "This text can run commands because the program does not protect inserted text.", ["Insert", "Cancel"])
        case .openLink:
            ("Open this link?", "This link can open another app or a file.", ["Open", "Cancel"])
        case .connectionFailure(let detail):
            ("The session is not available", detail, ["OK"])
        }
    }

    @MainActor
    func makeAlert() -> NSAlert {
        let alert = NSAlert()
        let words = words
        alert.messageText = words.title
        alert.informativeText = words.message
        for button in words.buttons { alert.addButton(withTitle: button) }
        if case .openLink(let address) = self {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 100))
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            let text = NSTextView(frame: scroll.bounds)
            text.isEditable = false
            text.isSelectable = true
            text.isVerticallyResizable = true
            text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]
            text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
            text.textContainer?.widthTracksTextView = true
            text.string = address
            scroll.documentView = text
            alert.accessoryView = scroll
        }
        return alert
    }

    @MainActor
    func ask(in window: NSWindow) async -> Bool {
        let alert = makeAlert()
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }
}
