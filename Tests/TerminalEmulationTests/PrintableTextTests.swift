import Testing
import TerminalEmulation

@Suite struct PrintableTextTests {
    @Test func plainTextStaysAsItIs() {
        #expect(PrintableText.escaping("") == "")
        #expect(PrintableText.escaping("/Users/someone/My Folder") == "/Users/someone/My Folder")
    }

    @Test func accentedLettersAndPictureSymbolsStayAsTheyAre() {
        let text = "caf\u{E9} \u{65E5}\u{672C}\u{8A9E} \u{1F600} \u{A0} \u{2028}"
        #expect(PrintableText.escaping(text) == text)
    }

    @Test func aBackSlashBecomesTwoBackSlashes() {
        #expect(PrintableText.escaping("a\\b") == "a\\\\b")
        // Without this rule the text `\n` and a real new line would look the same.
        #expect(PrintableText.escaping("\\n") == "\\\\n")
    }

    @Test func tabNewLineAndCarriageReturnHaveShortNames() {
        #expect(PrintableText.escaping("a\tb\nc\rd") == "a\\tb\\nc\\rd")
    }

    @Test func escapeBecomesItsCodeNumber() {
        #expect(PrintableText.escaping("\u{1B}]52;c;QUJD\u{07}") == "\\u{1B}]52;c;QUJD\\u{7}")
    }

    @Test func everyControlCharacterIsReplaced() {
        let shortNames: [UInt32: String] = [0x09: "\\t", 0x0A: "\\n", 0x0D: "\\r"]
        let controls: [UInt32] = Array(0x00...0x1F) + [0x7F] + Array(0x80...0x9F)
        for value in controls {
            let scalar = Unicode.Scalar(value)!
            let expected = shortNames[value] ?? "\\u{" + String(value, radix: 16, uppercase: true) + "}"
            #expect(PrintableText.escaping(String(scalar)) == expected, "U+\(String(value, radix: 16))")
        }
    }

    @Test func aCarriageReturnFollowedByANewLineKeepsBothEscapes() {
        // Swift treats "\r\n" as one character, and the escape must not miss it.
        #expect(PrintableText.escaping("a\r\nb") == "a\\r\\nb")
    }

    @Test func theResultHoldsNoControlCharacter() {
        var text = ""
        for value in UInt32(0)...0x9F { text.unicodeScalars.append(Unicode.Scalar(value)!) }
        let result = PrintableText.escaping(text)
        #expect(!result.unicodeScalars.contains { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) })
    }
}
