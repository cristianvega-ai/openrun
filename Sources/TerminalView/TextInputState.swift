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
    /// - Returns: `true` when the text waits for the end of the key. It is
    ///   `false` between keys, and then the caller must use the text at once.
    mutating func insert(_ text: String) -> Bool {
        markedText = ""
        guard committedTexts != nil else { return false }
        committedTexts?.append(text)
        return true
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
