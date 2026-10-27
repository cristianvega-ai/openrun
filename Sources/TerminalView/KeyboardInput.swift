import AppKit
import TerminalEmulation
import os

/// Turns the key events of AppKit into the bytes that a program reads, with
/// the key encoder of libghostty-vt.
@MainActor
final class KeyboardInput {
    private let terminal: Terminal
    private let encoder: KeyEncoder
    private let logger = Logger(subsystem: "ai.cristianvega.openrun", category: "KeyboardInput")

    init(terminal: Terminal) throws {
        self.terminal = terminal
        encoder = try KeyEncoder()
    }

    /// The bytes for a key that went down. They are empty for a key that sends nothing.
    func bytes(forKeyDown event: NSEvent) -> [UInt8] {
        encode(event, action: event.isARepeat ? .repeated : .press, text: KeyboardEventReader.layoutText(of: event))
    }

    private func encode(_ event: NSEvent, action: KeyEvent.Action, text: String?) -> [UInt8] {
        // The program can change its modes at any time, and the left Option key is Alt.
        encoder.update(from: terminal, optionAsAlternate: .leftOnly)
        do {
            return try encoder.encode(KeyboardEventReader.keyEvent(from: event, action: action, text: text))
        } catch {
            logger.error("A key failed: \(String(describing: error), privacy: .private)")
            return []
        }
    }
}
