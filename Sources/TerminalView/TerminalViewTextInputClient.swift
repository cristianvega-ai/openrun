import AppKit

/// The text input system of macOS talks to the view through `NSTextInputClient`.
/// Dead keys and input methods for Japanese, Chinese and Korean need it.
extension TerminalView: @MainActor NSTextInputClient {
    public func insertText(_ string: Any, replacementRange: NSRange) {
        sendTyped(keyboard.bytes(forInsertedText: Self.plainText(of: string)))
        showMarkedText()
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        keyboard.textInput.mark(Self.plainText(of: string))
        showMarkedText()
    }

    /// An input method can call this to commit text. The documents of Apple do
    /// not say so for sure, and a program must not read text that the user
    /// did not commit, so the view drops the text.
    public func unmarkText() {
        keyboard.textInput.unmark()
        showMarkedText()
    }

    public func hasMarkedText() -> Bool { keyboard.textInput.hasMarkedText }

    public func markedRange() -> NSRange {
        let length = keyboard.textInput.markedText.utf16.count
        return length > 0 ? NSRange(location: 0, length: length) : NSRange(location: NSNotFound, length: 0)
    }

    // The view does not give the text around the cursor to help conversion.
    public func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    public func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    /// An input method puts its list of candidates here, in the coordinates of the screen.
    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        window?.convertToScreen(convert(bounds, to: nil)) ?? bounds
    }

    /// The system gives a command, such as `deleteBackward:`, for keys that
    /// make no text. The view notes it, and the key encoder makes the bytes.
    public override func doCommand(by selector: Selector) {
        keyboard.textInput.record(selector)
    }

    private func showMarkedText() {
        renderer.markedText = keyboard.textInput.hasMarkedText ? keyboard.textInput.markedText : nil
        requestFrame()
    }

    private static func plainText(of string: Any) -> String {
        (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    }
}
