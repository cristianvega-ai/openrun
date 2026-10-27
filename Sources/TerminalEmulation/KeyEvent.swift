/// One key press, repeat or release, in the terms of libghostty-vt.
public struct KeyEvent: Sendable {
    public enum Action: Sendable { case press, repeated, release }

    public var action: Action
    public var key: PhysicalKey
    public var modifiers: KeyModifiers
    /// The modifiers that the keyboard layout used to make `text`, such as
    /// Shift for "A" or Option for "©".
    public var consumedModifiers: KeyModifiers
    /// The text of the key in the current layout, before Control. `nil` for
    /// keys that make no text and for control characters.
    public var text: String?
    /// The character of the key with no modifier, such as "a" for Shift-A.
    public var unshiftedScalar: Unicode.Scalar?
    /// Whether an input method is composing text with this key.
    public var isComposing: Bool

    public init(
        action: Action, key: PhysicalKey, modifiers: KeyModifiers = [], consumedModifiers: KeyModifiers = [],
        text: String? = nil, unshiftedScalar: Unicode.Scalar? = nil, isComposing: Bool = false
    ) {
        self.action = action
        self.key = key
        self.modifiers = modifiers
        self.consumedModifiers = consumedModifiers
        self.text = text
        self.unshiftedScalar = unshiftedScalar
        self.isComposing = isComposing
    }
}
