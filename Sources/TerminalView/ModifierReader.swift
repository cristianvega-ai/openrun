import AppKit
import Carbon.HIToolbox
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

    /// Whether the left Option key is down and the right one is not. When both
    /// Option keys are down, the right key wins.
    static func isLeftOption(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option) && flags.rawValue & DeviceBit.rightOption == 0
    }

    /// Whether the Option key that is down acts as Alt under `rule`.
    static func isAlternate(_ flags: NSEvent.ModifierFlags, rule: OptionKeyRule) -> Bool {
        switch rule {
        case .left: isLeftOption(flags)
        case .both: flags.contains(.option)
        case .neither: false
        }
    }

    /// The flags that the keyboard layout and the input methods see. They do
    /// not see an Option key that is Alt, because Alt must not change the text.
    static func translationFlags(_ flags: NSEvent.ModifierFlags, rule: OptionKeyRule = .left) -> NSEvent.ModifierFlags {
        guard isAlternate(flags, rule: rule) else { return flags }
        return flags.subtracting([.option, NSEvent.ModifierFlags(rawValue: DeviceBit.leftOption | DeviceBit.rightOption)])
    }

    /// Whether the modifier key with this key code is down, or `nil` for a key that is no modifier.
    /// A flag stays set while the other key of the same modifier is down, so the device bit tells.
    static func isKeyDown(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool? {
        guard let (flag, bit) = modifierKeys[Int(keyCode)] else { return nil }
        let hasDeviceBits = flags.rawValue & allDeviceBits != 0
        return bit != 0 && hasDeviceBits ? flags.rawValue & bit != 0 : flags.contains(flag)
    }

    private static let allDeviceBits: UInt = DeviceBit.leftControl | DeviceBit.leftShift | DeviceBit.rightShift
        | DeviceBit.leftCommand | DeviceBit.rightCommand | DeviceBit.leftOption | DeviceBit.rightOption | DeviceBit.rightControl

    private static let modifierKeys: [Int: (NSEvent.ModifierFlags, UInt)] = [
        kVK_Shift: (.shift, DeviceBit.leftShift), kVK_RightShift: (.shift, DeviceBit.rightShift),
        kVK_Control: (.control, DeviceBit.leftControl), kVK_RightControl: (.control, DeviceBit.rightControl),
        kVK_Option: (.option, DeviceBit.leftOption), kVK_RightOption: (.option, DeviceBit.rightOption),
        kVK_Command: (.command, DeviceBit.leftCommand), kVK_RightCommand: (.command, DeviceBit.rightCommand),
        kVK_CapsLock: (.capsLock, 0),
    ]
}
