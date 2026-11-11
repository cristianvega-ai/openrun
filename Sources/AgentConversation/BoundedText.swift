/// Cuts text from an agent or a tool to a limit of bytes.
///
/// A tool can print gigabytes, and the agent passes its output on. Every
/// text that the conversation keeps goes through this cut, so the memory of
/// a thread stays bounded whatever the agent sends.
public enum BoundedText {
    /// The start of `text`, at most `byteLimit` bytes of UTF-8. The cut
    /// falls at the end of a Unicode scalar, never inside one.
    public static func prefix(of text: String, byteLimit: Int) -> String {
        let utf8 = text.utf8
        guard utf8.count > byteLimit else { return text }
        var end = utf8.index(utf8.startIndex, offsetBy: max(0, byteLimit))
        while end > utf8.startIndex, end.samePosition(in: text.unicodeScalars) == nil {
            end = utf8.index(before: end)
        }
        return String(text[..<end])
    }

    /// The start of `bytes` as text, at most `byteLimit` bytes. A cut that
    /// falls inside a character moves back to its first byte. Bytes that
    /// are not UTF-8 become the replacement character.
    public static func prefix(of bytes: some Collection<UInt8>, byteLimit: Int) -> String {
        var kept = Array(bytes.prefix(max(0, byteLimit)))
        // A byte of the form 10xxxxxx continues a character. The first
        // byte of a character tells its length.
        if kept.count < bytes.count, let start = kept.lastIndex(where: { $0 & 0xC0 != 0x80 }) {
            let lead = kept[start]
            let length = lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 1
            if kept.count - start < length { kept.removeSubrange(start...) }
        }
        return String(decoding: kept, as: UTF8.self)
    }
}
