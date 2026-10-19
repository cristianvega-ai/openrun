struct DetachKeyRecognizer {
    private static let escape: UInt8 = 0x1B
    private static let controlBracket: UInt8 = 0x1D
    /// The last byte of the kitty form, `u`, and of the modifyOtherKeys form, `~`.
    private static let kittyFinalByte: UInt8 = 0x75
    private static let modifyOtherKeysFinalByte: UInt8 = 0x7E

    /// `27 ; 5 ; 93`. Fields before the last must be complete.
    private static func couldBeModifyOtherKeysForm(_ fields: [[UInt8]]) -> Bool {
        let expected = ["27", "5", "93"]
        guard fields.count <= expected.count else { return false }
        for (position, field) in fields.enumerated() {
            let isLast = position == fields.count - 1
            if isLast ? !Array(expected[position].utf8).starts(with: field) : field != Array(expected[position].utf8) {
                return false
            }
        }
        return true
    }

    /// `93[:alternates] ; modifiers[:event] [; text]`.
    private static func couldBeKittyForm(_ fields: [[UInt8]]) -> Bool {
        let digitsAndColons = { (field: [UInt8]) in
            field.allSatisfy { (0x30...0x39).contains($0) || $0 == UInt8(ascii: ":") }
        }
        guard fields.count <= 3 else { return false }
        let key = fields[0]
        let keyStart = Array("93".utf8)
        let keyHasAlternates = key.starts(with: Array("93:".utf8)) && digitsAndColons(key)
        if fields.count == 1 { return keyStart.starts(with: key) || keyHasAlternates }
        return (key == keyStart || keyHasAlternates) && fields.dropFirst().allSatisfy(digitsAndColons)
    }

    private static func isDetachKey(parameters: [UInt8], final: UInt8) -> Bool {
        let fields = parameters.split(separator: UInt8(ascii: ";"), omittingEmptySubsequences: false)
        switch final {
        case kittyFinalByte:
            return isKittyDetachKey(fields: fields)
        case modifyOtherKeysFinalByte:
            return fields.count == 3 && number(fields[0]) == 27 && number(fields[1]) == 5 && number(fields[2]) == 93
        default:
            return false
        }
    }

    /// The kitty form: `93[:alternates] ; modifiers[:event] [; text]`.
    private static func isKittyDetachKey(fields: [ArraySlice<UInt8>]) -> Bool {
        guard fields.count >= 2 else { return false }
        let keyParts = fields[0].split(separator: UInt8(ascii: ":"), omittingEmptySubsequences: false)
        guard let key = keyParts.first, number(key) == 93 else { return false }

        let modifierParts = fields[1].split(separator: UInt8(ascii: ":"), omittingEmptySubsequences: false)
        guard let modifierValue = modifierParts.first.flatMap({ number($0) }), modifierValue >= 1 else { return false }
        // The value is one more than the bits. Caps Lock (64) and Num Lock
        // (128) do not change which key the person pressed.
        let lockKeyBits = 64 | 128
        let pressedModifiers = (modifierValue - 1) & ~lockKeyBits
        let control = 4
        guard pressedModifiers == control else { return false }

        guard modifierParts.count > 1, !modifierParts[1].isEmpty else { return true }
        // Press is 1 and repeat is 2. Release is 3, and is not a press.
        let event = number(modifierParts[1])
        return event == 1 || event == 2
    }

    private static func number(_ digits: ArraySlice<UInt8>) -> Int? {
        guard !digits.isEmpty, digits.count <= 6, digits.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return digits.reduce(0) { $0 * 10 + Int($1 - 0x30) }
    }
}
