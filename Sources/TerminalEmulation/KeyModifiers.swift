import GhosttyVt

/// The modifier keys of a key or mouse event. The bit values are those of
/// libghostty-vt.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let shift = KeyModifiers(rawValue: UInt16(GHOSTTY_MODS_SHIFT))
    public static let control = KeyModifiers(rawValue: UInt16(GHOSTTY_MODS_CTRL))
    /// Alt, the Option key on a Mac.
    public static let alternate = KeyModifiers(rawValue: UInt16(GHOSTTY_MODS_ALT))
    /// Super, the Command key on a Mac.
    public static let superKey = KeyModifiers(rawValue: UInt16(GHOSTTY_MODS_SUPER))
    public static let capsLock = KeyModifiers(rawValue: UInt16(GHOSTTY_MODS_CAPS_LOCK))
    public static let numberLock = KeyModifiers(rawValue: UInt16(GHOSTTY_MODS_NUM_LOCK))
    public static let rightShift = KeyModifiers(rawValue: UInt16(GHOSTTY_MODS_SHIFT_SIDE))
    public static let rightControl = KeyModifiers(rawValue: UInt16(GHOSTTY_MODS_CTRL_SIDE))
    public static let rightAlternate = KeyModifiers(rawValue: UInt16(GHOSTTY_MODS_ALT_SIDE))
    public static let rightSuperKey = KeyModifiers(rawValue: UInt16(GHOSTTY_MODS_SUPER_SIDE))
}
