struct DetachKeyRecognizer {
    /// How long an incomplete start of a detach form waits for the rest. A
    /// lone Escape key press reaches the program this much later.
    static let holdDuration: Duration = .milliseconds(20)

    /// What one read of keys means.
    struct Scan: Equatable {
        /// The bytes to send to the session. When the detach key was found,
        /// these are the bytes before it.
        var bytesToSend: [UInt8]
        var foundDetachKey: Bool
    }

    private static let escape: UInt8 = 0x1B
    private static let controlBracket: UInt8 = 0x1D
    /// The last byte of the kitty form, `u`, and of the modifyOtherKeys form, `~`.
    private static let kittyFinalByte: UInt8 = 0x75
    private static let modifyOtherKeysFinalByte: UInt8 = 0x7E

    /// The longest escape sequence we hold back. A longer one is no key press
    /// that we know, so it is sent on.
    private static let longestHeldSequence = 64

    /// The start of a detach form that the last read cut short.
    private var heldBytes: [UInt8] = []
    /// When the held bytes must be sent on.
    private var holdDeadline: ContinuousClock.Instant?

    /// How long the caller may wait for more keys before it must call
    /// `releaseExpired`, or `nil` when nothing is held.
    func remainingHold(at now: ContinuousClock.Instant) -> Duration? {
        guard let holdDeadline else { return nil }
        return max(.zero, holdDeadline - now)
    }

    /// The held bytes, when their time is up. They are keys for the program.
    mutating func releaseExpired(at now: ContinuousClock.Instant) -> [UInt8] {
        guard let holdDeadline, now >= holdDeadline else { return [] }
        defer {
            heldBytes = []
            self.holdDeadline = nil
        }
        return heldBytes
    }

    /// Looks at one read of keys. An incomplete end that could still become a
    /// detach form waits for the next read, until `holdDuration` has passed.
    mutating func scan(_ bytes: [UInt8], at now: ContinuousClock.Instant) -> Scan {
        let previouslyHeld = heldBytes.count
        let input = heldBytes + bytes
        heldBytes = []
        let previousDeadline = holdDeadline
        holdDeadline = nil
        var bytesToSend: [UInt8] = []
        var index = 0
        while index < input.count {
            let byte = input[index]
            if byte == Self.controlBracket {
                return Scan(bytesToSend: bytesToSend, foundDetachKey: true)
            }
            guard byte == Self.escape else {
                bytesToSend.append(byte)
                index += 1
                continue
            }
            switch Self.sequence(in: input, startingAt: index) {
            case .detachKey:
                return Scan(bytesToSend: bytesToSend, foundDetachKey: true)
            case .otherSequence(let length):
                bytesToSend.append(contentsOf: input[index..<index + length])
                index += length
            case .incomplete(let couldBeDetachKey):
                let held = Array(input[index...])
                if couldBeDetachKey && held.count <= Self.longestHeldSequence {
                    heldBytes = held
                    // Bytes that were already waiting keep their deadline, so
                    // a slow typist cannot extend the hold.
                    holdDeadline = index == 0 && previouslyHeld > 0 ? previousDeadline : now + Self.holdDuration
                    return Scan(bytesToSend: bytesToSend, foundDetachKey: false)
                }
                bytesToSend.append(byte)
                index += 1
            case .notASequence:
                bytesToSend.append(byte)
                index += 1
            }
        }
        return Scan(bytesToSend: bytesToSend, foundDetachKey: false)
    }

    // MARK: - Reading one sequence

    private enum Sequence {
        case detachKey
        case otherSequence(length: Int)
        /// The end of the input cuts the sequence short.
        /// `couldBeDetachKey` is false when no detach form starts like this.
        case incomplete(couldBeDetachKey: Bool)
        case notASequence
    }

    /// Reads the control sequence that starts with the escape byte at `start`.
    private static func sequence(in input: [UInt8], startingAt start: Int) -> Sequence {
        guard start + 1 < input.count else { return .incomplete(couldBeDetachKey: true) }
        guard input[start + 1] == UInt8(ascii: "[") else { return .notASequence }
        var index = start + 2
        while index < input.count {
            let byte = input[index]
            if (0x40...0x7E).contains(byte) {
                let parameters = Array(input[(start + 2)..<index])
                let isDetachKey = isDetachKey(parameters: parameters, final: byte)
                return isDetachKey ? .detachKey : .otherSequence(length: index + 1 - start)
            }
            // Parameter bytes are 0x30...0x3F and intermediate bytes 0x20...0x2F.
            guard (0x20...0x3F).contains(byte) else { return .notASequence }
            index += 1
        }
        return .incomplete(couldBeDetachKey: couldBecomeDetachKey(parameters: Array(input[(start + 2)...])))
    }

    /// Whether the parameters so far are the start of a kitty or a
    /// modifyOtherKeys detach form. Only such a start is worth holding.
    private static func couldBecomeDetachKey(parameters: [UInt8]) -> Bool {
        // Parameter bytes only. An intermediate byte starts no form we know.
        guard parameters.allSatisfy({ (0x30...0x3F).contains($0) }) else { return false }
        let fields = parameters.split(separator: UInt8(ascii: ";"), omittingEmptySubsequences: false).map(Array.init)
        return couldBeModifyOtherKeysForm(fields) || couldBeKittyForm(fields)
    }

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
