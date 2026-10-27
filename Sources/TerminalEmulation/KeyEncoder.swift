import GhosttyVt

/// Encodes key events into the bytes a program reads, with the modes and
/// the kitty keyboard flags that the program set in the terminal.
public final class KeyEncoder {
    /// Which Option keys act as Alt. With `.never`, Option types characters.
    public enum OptionAsAlternate: Sendable { case never, always, leftOnly, rightOnly }

    private let encoder: GhosttyKeyEncoder
    private let event: GhosttyKeyEvent

    public init() throws {
        var encoder: GhosttyKeyEncoder?
        var event: GhosttyKeyEvent?
        try TerminalEmulationError.check(ghostty_key_encoder_new(nil, &encoder), from: "ghostty_key_encoder_new")
        guard ghostty_key_event_new(nil, &event) == GHOSTTY_SUCCESS, let encoder, let event else {
            ghostty_key_encoder_free(encoder)
            throw TerminalEmulationError.invalidValue(in: "KeyEncoder.init")
        }
        self.encoder = encoder
        self.event = event
    }

    deinit {
        ghostty_key_event_free(event)
        ghostty_key_encoder_free(encoder)
    }

    /// Reads the modes of the terminal. Call it before each key, because the
    /// program can change them at any time. libghostty-vt resets Option as
    /// Alt in this call, so the setting follows it.
    public func update(from terminal: Terminal, optionAsAlternate: OptionAsAlternate = .never) {
        ghostty_key_encoder_setopt_from_terminal(encoder, terminal.handle)
        var option: GhosttyOptionAsAlt = switch optionAsAlternate {
        case .never: GHOSTTY_OPTION_AS_ALT_FALSE
        case .always: GHOSTTY_OPTION_AS_ALT_TRUE
        case .leftOnly: GHOSTTY_OPTION_AS_ALT_LEFT
        case .rightOnly: GHOSTTY_OPTION_AS_ALT_RIGHT
        }
        ghostty_key_encoder_setopt(encoder, GHOSTTY_KEY_ENCODER_OPT_MACOS_OPTION_AS_ALT, &option)
    }

    /// The bytes for the program. Empty when the key sends nothing, such as
    /// a modifier key alone or a release outside the kitty protocol.
    public func encode(_ key: KeyEvent) throws -> [UInt8] {
        let action: GhosttyKeyAction = switch key.action {
        case .press: GHOSTTY_KEY_ACTION_PRESS
        case .repeated: GHOSTTY_KEY_ACTION_REPEAT
        case .release: GHOSTTY_KEY_ACTION_RELEASE
        }
        ghostty_key_event_set_action(event, action)
        ghostty_key_event_set_key(event, key.key.raw)
        ghostty_key_event_set_mods(event, key.modifiers.rawValue)
        ghostty_key_event_set_consumed_mods(event, key.consumedModifiers.rawValue)
        ghostty_key_event_set_composing(event, key.isComposing)
        ghostty_key_event_set_unshifted_codepoint(event, key.unshiftedScalar?.value ?? 0)
        // The event borrows the text, so it is set and used in one scope.
        return try Array((key.text ?? "").utf8).withUnsafeBufferPointer { text in
            text.withMemoryRebound(to: CChar.self) { ghostty_key_event_set_utf8(event, $0.baseAddress, $0.count) }
            defer { ghostty_key_event_set_utf8(event, nil, 0) }
            // A sequence is short, and a key that sends its text sends no more.
            var output = [UInt8](repeating: 0, count: 64 + text.count)
            var written = 0
            let result = output.withUnsafeMutableBytes {
                ghostty_key_encoder_encode(encoder, event, $0.baseAddress?.assumingMemoryBound(to: CChar.self), $0.count, &written)
            }
            try TerminalEmulationError.check(result, from: "ghostty_key_encoder_encode")
            return Array(output.prefix(written))
        }
    }
}
