import Testing
@testable import UntrustedText

@Suite struct UntrustedTextTests {
    @Test func aPlainNameHasNoControlBreakOrDirectionChange() {
        #expect(PlainName.isValid("Graphite Dark ✨", lengthLimit: 100))
        #expect(PlainName.isValid("👩‍💻", lengthLimit: 1))
        #expect(PlainName.isValid("a\u{200B}b", lengthLimit: 100))
        #expect(!PlainName.isValid("", lengthLimit: 100))
        #expect(PlainName.isValid("", lengthLimit: 100, allowsEmpty: true))
        #expect(!PlainName.isValid("abc", lengthLimit: 2))
        let bad: [Unicode.Scalar] = [
            "\n", "\t", "\u{1B}", "\u{7F}", "\u{9B}", "\u{2028}", "\u{2029}",
            "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
            "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{200E}", "\u{200F}", "\u{061C}",
        ]
        for scalar in bad {
            #expect(!PlainName.isValid("a" + String(Character(scalar)) + "b", lengthLimit: 100), "U+\(String(scalar.value, radix: 16))")
        }
    }

    @Test func quotedTextShowsEachControlAndFormatCharacterAsAnEscape() {
        #expect(QuotedText.quoted("font") == #""font""#)
        #expect(QuotedText.quoted("/work/a\u{1B}[2Jb") == #""/work/a\u{1B}[2Jb""#)
        #expect(QuotedText.quoted("a\u{202E}b\u{200B}c\u{9B}\u{2028}") == #""a\u{202E}b\u{200B}c\u{9B}\u{2028}""#)
        #expect(QuotedText.quoted(#"say "hi" \ bye"#) == #""say \"hi\" \\ bye""#)
        #expect(QuotedText.quoted(String(repeating: "x", count: 70), characterLimit: 64)
            == "\"" + String(repeating: "x", count: 64) + "…\"")
        #expect(QuotedText.quoted(String(repeating: "x", count: 256)) == "\"" + String(repeating: "x", count: 256) + "\"")
    }
}
