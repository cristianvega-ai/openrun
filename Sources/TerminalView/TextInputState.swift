import Foundation

/// What the text input system tells a view. An input method keeps text that
/// the user did not commit yet, which is the marked text. While the view
/// handles one key, the system also gives the texts that the key committed,
/// and the commands that it ran, such as `deleteBackward:`.
struct TextInputState {
    private(set) var markedText = ""
    /// The texts that the key now handled committed, or `nil` between keys.
    private var committedTexts: [String]?
    private var commands: [Selector] = []

    var hasMarkedText: Bool { !markedText.isEmpty }

    mutating func mark(_ text: String) {
        markedText = text
    }

    /// Ends the marked text without a commit.
    mutating func unmark() {
        markedText = ""
    }

    mutating func beginKey() {
        committedTexts = []
        commands = []
    }

    /// Commits text, which ends the marked text.
    ///
    /// - Returns: The text that the caller must use at once, because no key waits for it.
    ///   It is `nil` when the text waits for the end of the key, or when the state drops it.
    mutating func insert(_ text: String) -> String? {
        // A control key such as Control-c can give its control character as text
        // while an input method holds marked text. The program must not read it.
        if hasMarkedText, !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value < 0x20 }) { return nil }
        markedText = ""
        guard committedTexts != nil else { return text }
        committedTexts?.append(text)
        return nil
    }

    /// Notes a command of the text input system. The view does not run it,
    /// because the key encoder decides the bytes of keys such as Return.
    mutating func record(_ command: Selector) {
        if committedTexts != nil { commands.append(command) }
    }

    /// Ends the key and gives what it committed and ran.
    mutating func endKey() -> (texts: [String], commands: [Selector]) {
        defer { (committedTexts, commands) = (nil, []) }
        return (committedTexts ?? [], commands)
    }
}
