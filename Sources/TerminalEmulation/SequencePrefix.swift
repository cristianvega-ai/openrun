/// The first bytes of an escape sequence, one byte in each eight bits of a
/// number, and the count of all its bytes. Eight bytes tell apart every
/// sequence that `ShellPromptScanner` looks for, and a number needs no memory
/// for each sequence of the output.
struct SequencePrefix: Sendable, Equatable {
    private(set) var bytes: UInt64 = 0
    private(set) var count = 0

    init(_ text: String = "") {
        for byte in text.utf8 { append(byte) }
    }

    mutating func append(_ byte: UInt8) {
        if count < 8 { bytes |= UInt64(byte) << (8 * count) }
        count += 1
    }

    /// The first `length` bytes, when a semicolon or the end follows them.
    func kind(length: Int) -> UInt64? {
        let follower = (bytes >> (8 * UInt64(length))) & 0xff
        guard count == length || (count > length && follower == UInt64(UInt8(ascii: ";"))) else { return nil }
        return bytes & ((1 << (8 * UInt64(length))) - 1)
    }
}
