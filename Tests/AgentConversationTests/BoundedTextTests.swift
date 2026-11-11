import Testing
import AgentConversation

@Suite struct BoundedTextTests {
    @Test func shortTextStaysWhole() {
        #expect(BoundedText.prefix(of: "ok", byteLimit: 2) == "ok")
        #expect(BoundedText.prefix(of: Array("ok".utf8), byteLimit: 10) == "ok")
    }

    @Test func aCutNeverSplitsAScalar() {
        // "é" is two bytes and "😀" four, so most limits fall inside one.
        let text = "aé😀b"
        for limit in 0...8 {
            let cut = BoundedText.prefix(of: text, byteLimit: limit)
            let cutBytes = BoundedText.prefix(of: Array(text.utf8), byteLimit: limit)
            #expect(cut.utf8.count <= limit)
            #expect(text.hasPrefix(cut))
            #expect(cutBytes == cut, "limit \(limit)")
        }
        #expect(BoundedText.prefix(of: text, byteLimit: 3) == "aé")
        #expect(BoundedText.prefix(of: text, byteLimit: 6) == "aé")
        #expect(BoundedText.prefix(of: text, byteLimit: 7) == "aé😀")
    }

    @Test func bytesThatAreNotTextDoNotTrap() {
        let bytes: [UInt8] = [0xFF, 0xC3, 0x28, 0x80, 0x80, 0xF0, 0x9F]
        for limit in 0...bytes.count + 1 {
            _ = BoundedText.prefix(of: bytes, byteLimit: limit)
        }
        #expect(BoundedText.prefix(of: [UInt8](), byteLimit: -1) == "")
        #expect(BoundedText.prefix(of: "text", byteLimit: -1) == "")
    }

    @Test func aSourceLineKeepsOnlyItsStartAndItsLength() {
        let long = [UInt8](repeating: UInt8(ascii: "x"), count: SourceLine.byteLimit * 3)
        let line = SourceLine(bytes: long)
        #expect(line.text.utf8.count == SourceLine.byteLimit)
        #expect(line.byteCount == long.count)
        #expect(!line.isComplete)
        #expect(SourceLine(bytes: Array("{}".utf8)).isComplete)
    }
}
