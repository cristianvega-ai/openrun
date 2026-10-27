/// The rule for a paste that asks the user first. A paste is unsafe when it has a
/// line break and the program did not turn on bracketed paste. Then the shell
/// runs each line at once. With bracketed paste the program knows the text came
/// from a paste, so even many lines are safe, as in the prompt of an agent.
enum UnsafePasteRule {
    static func needsQuestion(for text: String, bracketedPaste: Bool) -> Bool {
        !bracketedPaste && text.unicodeScalars.contains { $0 == "\n" || $0 == "\r" }
    }
}
