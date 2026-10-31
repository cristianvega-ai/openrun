/// Where text with a line break came from when no key press made it. The owner
/// asks a different question for each source, so the words of the question fit.
enum UnsafeTextSource {
    /// Command-V or the Paste menu.
    case paste
    /// Dictation, a Service, or an input-method candidate that the user chose outside a key event.
    case insertion

    @MainActor
    func approval(of text: String, from view: TerminalView, by delegate: TerminalViewDelegate) async -> Bool {
        switch self {
        case .paste: await delegate.terminalView(view, shouldPasteUnsafeText: text)
        case .insertion: await delegate.terminalView(view, shouldInsertUnsafeText: text)
        }
    }
}
