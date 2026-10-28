import AppKit

/// A question that belongs to one session window.
enum UserQuestion: Equatable, Sendable {
    case unsafePaste
    case connectionFailure(String)

    var words: (title: String, message: String, buttons: [String]) {
        switch self {
        case .unsafePaste:
            ("Paste multiple lines?", "This paste can run commands because the program does not protect pasted text.", ["Paste", "Cancel"])
        case .connectionFailure(let detail):
            ("The session is not available", detail, ["OK"])
        }
    }

    @MainActor
    func ask(in window: NSWindow) async -> Bool {
        let alert = NSAlert()
        let words = words
        alert.messageText = words.title
        alert.informativeText = words.message
        for button in words.buttons { alert.addButton(withTitle: button) }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }
}
