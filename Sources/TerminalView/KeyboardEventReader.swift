import AppKit
import TerminalEmulation

/// Makes the `KeyEvent` of libghostty-vt from a key event of AppKit.
enum KeyboardEventReader {
    /// - Parameters:
    ///   - text: The text that the key made, from the text input system or from the layout.
    ///   - isComposing: Whether an input method holds marked text.
    static func keyEvent(from event: NSEvent, action: KeyEvent.Action, text: String?, isComposing: Bool = false) -> KeyEvent {
        let flags = event.modifierFlags
        // Control and Command never make text on a Mac. Shift and the right
        // Option key do, so the encoder must not count them a second time.
        let consumed = ModifierReader.translationFlags(flags).subtracting([.control, .command, .capsLock])
        // Only key events have characters. AppKit raises an exception for the others.
        let isKey = event.type == .keyDown || event.type == .keyUp
        return KeyEvent(
            action: action, key: KeyCodeTable.physicalKey(forKeyCode: event.keyCode),
            modifiers: ModifierReader.modifiers(of: flags), consumedModifiers: ModifierReader.modifiers(of: consumed),
            text: encoderText(text), unshiftedScalar: isKey ? event.characters(byApplyingModifiers: [])?.unicodeScalars.first : nil,
            isComposing: isComposing)
    }

    /// The text of the key in the current layout. It leaves out the left Option
    /// key, which is Alt, and Control, because the encoder makes the control
    /// characters from the key.
    static func layoutText(of event: NSEvent) -> String? {
        event.characters(byApplyingModifiers: ModifierReader.translationFlags(event.modifierFlags).subtracting(.control))
    }

    /// libghostty-vt wants no control characters as text. It wants no function
    /// key characters of AppKit (the private use area U+F700 to U+F8FF) either.
    static func encoderText(_ text: String?) -> String? {
        guard let scalars = text?.unicodeScalars, let first = scalars.first else { return nil }
        if scalars.count == 1, first.value < 0x20 || first.value == 0x7F || (0xF700...0xF8FF).contains(first.value) { return nil }
        return text
    }
}
