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
}
