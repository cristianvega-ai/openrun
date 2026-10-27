import TerminalEmulation
import os

/// Makes the bytes of a paste for the program.
@MainActor
enum PasteInput {
    private static let logger = Logger(subsystem: "ai.cristianvega.openrun", category: "PasteInput")

    /// The text in a bracketed paste when the program turned mode 2004 on. Otherwise
    /// the line feeds become carriage returns, as a key Return does.
    static func bytes(for text: String, terminal: Terminal) -> [UInt8] {
        do {
            return try PasteText(text).encoded(for: terminal)
        } catch {
            logger.error("A paste failed: \(String(describing: error), privacy: .private)")
            return []
        }
    }
}
