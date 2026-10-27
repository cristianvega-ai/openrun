import AppKit
import TerminalEmulation
import os

/// Turns the key events of AppKit into the bytes that a program reads, with
/// the key encoder of libghostty-vt.
@MainActor
final class KeyboardInput {
    /// The marked text and the texts of the key now handled.
    var textInput = TextInputState()
    var layout = KeyboardLayoutWatch()
    private let terminal: Terminal
    private let encoder: KeyEncoder
    private let logger = Logger(subsystem: "ai.cristianvega.openrun", category: "KeyboardInput")

    init(terminal: Terminal) throws {
        self.terminal = terminal
        encoder = try KeyEncoder()
    }

    /// The bytes for a key that went down. They are empty for a key that sends nothing.
    ///
    /// - Parameter interpret: Gives the key to the text input system, which
    ///   answers through `NSTextInputClient`. An input method needs it for
    ///   every key.
    func bytes(forKeyDown event: NSEvent, interpret: (NSEvent) -> Void) -> [UInt8] {
        let hadMarkedText = textInput.hasMarkedText
        // An input method can change its own input source while it composes, so only a key
        // with no marked text can tell a change of the layout.
        let layoutBefore = hadMarkedText ? nil : layout.identifier()
        textInput.beginKey()
        interpret(translationEvent(for: event))
        let key = textInput.endKey()
        // A key that changes the layout, such as a shortcut for the input source, sends nothing.
        guard hadMarkedText || layout.identifier() == layoutBefore else { return [] }
        let action: KeyEvent.Action = event.isARepeat ? .repeated : .press
        if hadMarkedText || textInput.hasMarkedText {
            // The input method owns the key. The text that it committed goes
            // to the program as it is. A command that it ran, such as
            // `deleteBackward:`, means that the key still has its own effect.
            let keyFollows = !textInput.hasMarkedText && !key.texts.isEmpty && !key.commands.isEmpty
            return key.texts.flatMap { Array($0.utf8) } + (keyFollows ? encode(event, action: action, text: nil) : [])
        }
        if key.texts.isEmpty { return encode(event, action: action, text: KeyboardEventReader.layoutText(of: event)) }
        return key.texts.flatMap { encode(event, action: action, text: $0) }
    }

    /// The text input system sees the key without the left Option key, so
    /// that Alt does not make a dead key. A copy is made only when the flags
    /// differ, because some input methods need the original event.
    private func translationEvent(for event: NSEvent) -> NSEvent {
        let flags = ModifierReader.translationFlags(event.modifierFlags)
        guard flags != event.modifierFlags else { return event }
        return NSEvent.keyEvent(
            with: event.type, location: event.locationInWindow, modifierFlags: flags, timestamp: event.timestamp,
            windowNumber: event.windowNumber, context: nil, characters: event.characters(byApplyingModifiers: flags) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "", isARepeat: event.isARepeat, keyCode: event.keyCode)
            ?? event
    }

    /// The bytes for a text that the text input system commits. There are none
    /// while a key waits for its end, because the key sends the text then.
    func bytes(forInsertedText text: String) -> [UInt8] {
        textInput.insert(text) ? [] : Array(text.utf8)
    }

    /// The bytes for a key that went up. Only a program that asked for key events reads them.
    func bytes(forKeyUp event: NSEvent) -> [UInt8] {
        encode(event, action: .release, text: nil)
    }

    /// The bytes for a modifier key that went down or up. Only a program that
    /// asked for all keys as escape codes reads them.
    func bytes(forFlagsChanged event: NSEvent) -> [UInt8] {
        guard let isDown = ModifierReader.isKeyDown(keyCode: event.keyCode, flags: event.modifierFlags) else { return [] }
        return encode(event, action: isDown ? .press : .release, text: nil)
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
