import AppKit
import TerminalEmulation

/// Reads the modifier keys of an event, with the side of each key. AppKit
/// shows the side only in the device bits of `modifierFlags`, and it has no
/// public names for them.
enum ModifierReader {
    /// The device bits from `NX_DEVICE...` in IOKit.
    enum DeviceBit {
        static let leftControl: UInt = 0x1
        static let leftShift: UInt = 0x2
        static let rightShift: UInt = 0x4
        static let leftCommand: UInt = 0x8
        static let rightCommand: UInt = 0x10
        static let leftOption: UInt = 0x20
        static let rightOption: UInt = 0x40
        static let rightControl: UInt = 0x2000
    }

    /// An event with no device bit counts as the left key, so a modifier that
    /// a program adds to an event acts as the key of a normal keyboard.
    static func modifiers(of flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var modifiers: KeyModifiers = []
        func add(_ flag: NSEvent.ModifierFlags, _ left: KeyModifiers, right: KeyModifiers, rightBit: UInt) {
            guard flags.contains(flag) else { return }
            modifiers.insert(left)
            if flags.rawValue & rightBit != 0 { modifiers.insert(right) }
        }
        add(.shift, .shift, right: .rightShift, rightBit: DeviceBit.rightShift)
        add(.control, .control, right: .rightControl, rightBit: DeviceBit.rightControl)
        add(.option, .alternate, right: .rightAlternate, rightBit: DeviceBit.rightOption)
        add(.command, .superKey, right: .rightSuperKey, rightBit: DeviceBit.rightCommand)
        if flags.contains(.capsLock) { modifiers.insert(.capsLock) }
        return modifiers
    }

    /// Whether Option acts as Alt. When both Option keys are down, the right
    /// key wins, and the key types a character.
    static func isLeftOption(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option) && flags.rawValue & DeviceBit.rightOption == 0
    }

    /// The flags that the keyboard layout and the input methods see. They do
    /// not see the left Option key, because Alt must not change the text.
    static func translationFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        guard isLeftOption(flags) else { return flags }
        return flags.subtracting([.option, NSEvent.ModifierFlags(rawValue: DeviceBit.leftOption)])
    }
}
