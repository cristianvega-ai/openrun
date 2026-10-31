import AppKit
import TerminalEmulation

/// The text input system of macOS talks to the view through `NSTextInputClient`.
/// Dead keys and input methods for Japanese, Chinese and Korean need it.
extension TerminalView: @MainActor NSTextInputClient {
    public func insertText(_ string: Any, replacementRange: NSRange) {
        if let text = keyboard.textInput.insert(Self.plainText(of: string)) { pasteText(text) }
        showMarkedText()
    }

    public func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        keyboard.textInput.mark(Self.plainText(of: string), selection: selectedRange)
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

    public func selectedRange() -> NSRange {
        guard hasMarkedText() else { return NSRange(location: NSNotFound, length: 0) }
        return keyboard.textInput.markedSelection ?? NSRange(location: keyboard.textInput.markedText.utf16.count, length: 0)
    }

    public func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let text = keyboard.textInput.markedText as NSString
        guard hasMarkedText(), range.location != NSNotFound, range.location >= 0, range.location <= text.length, range.length >= 0 else {
            actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
            return nil
        }
        let proposed = NSRange(location: range.location, length: min(range.length, text.length - range.location))
        let actual = proposed.length == 0 ? proposed : text.rangeOfComposedCharacterSequences(for: proposed)
        actualRange?.pointee = actual
        return NSAttributedString(string: text.substring(with: actual))
    }
    public func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    public func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    /// An input method puts its list of candidates at the cursor. The answer is
    /// the cell of the cursor in the coordinates of the screen.
    public func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let cursor = ViewportCell(column: terminal.cursorPosition.column, row: UInt32(terminal.cursorPosition.row))
        let position: ViewportCell
        if hasMarkedText() {
            let requested = range.location == NSNotFound ? nil : range
            guard let marked = renderer.markedTextCaretPosition(at: cursor, in: terminal.size, for: requested) else {
                actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
                return .zero
            }
            position = marked
            let text = keyboard.textInput.markedText as NSString
            let location = min(max(0, requested?.location ?? selectedRange().location), text.length)
            actualRange?.pointee = location < text.length ? text.rangeOfComposedCharacterSequence(at: location) : NSRange(location: text.length, length: 0)
        } else {
            position = cursor
            actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
        }
        let cell = cellSize
        // The row counts from the top of the view, and AppKit counts from the bottom.
        let rectangle = NSRect(
            x: gridPadding + CGFloat(position.column) * cell.width, y: bounds.height - gridPadding - CGFloat(position.row + 1) * cell.height,
            width: cell.width, height: cell.height)
        return window?.convertToScreen(convert(rectangle, to: nil)) ?? rectangle
    }

    /// The system gives a command, such as `deleteBackward:`, for keys that
    /// make no text. The view notes it, and the key encoder makes the bytes.
    public override func doCommand(by selector: Selector) {
        keyboard.textInput.record(selector)
    }

    private func showMarkedText() {
        renderer.markedText = keyboard.textInput.hasMarkedText ? keyboard.textInput.markedText : nil
        renderer.markedTextSelection = keyboard.textInput.markedSelection
        requestFrame()
    }

    private static func plainText(of string: Any) -> String {
        (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
    }
}
