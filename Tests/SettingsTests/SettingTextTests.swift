@testable import Settings
import Testing

@Suite struct SettingTextTests {
    @Test func plainTextHasNoControlCharacterOrLineBreak() {
        #expect(SettingText.isPlain("Graphite Dark ✨", lengthLimit: 100))
        #expect(SettingText.isPlain("👩‍💻", lengthLimit: 1))
        #expect(!SettingText.isPlain("", lengthLimit: 100))
        #expect(SettingText.isPlain("", lengthLimit: 100, allowsEmpty: true))
        #expect(!SettingText.isPlain("abc", lengthLimit: 2))
        for bad in ["a\nb", "a\tb", "a\u{1B}b", "a\u{7F}b", "a\u{9B}b", "a\u{2028}b", "a\u{2029}b"] {
            #expect(!SettingText.isPlain(bad, lengthLimit: 100))
        }
    }

    @Test func quotedTextShowsEachControlAndFormatCharacterAsAnEscape() {
        #expect(SettingText.quoted("font") == #""font""#)
        #expect(SettingText.quoted("a\u{1B}[2Jb") == #""a\u{1B}[2Jb""#)
        #expect(SettingText.quoted("a\u{202E}b\u{200B}c\u{9B}") == #""a\u{202E}b\u{200B}c\u{9B}""#)
        #expect(SettingText.quoted(#"say "hi" \ bye"#) == #""say \"hi\" \\ bye""#)
        #expect(SettingText.quoted(String(repeating: "x", count: 70)) == "\"" + String(repeating: "x", count: 64) + "…\"")
    }

    @Test func aCommandNeedsANameAndAPlainCommandLine() {
        #expect(NewSessionCommand.defaults.allSatisfy { $0.isValid })
        #expect(NewSessionCommand.defaults.map(\.commandLine) == ["", "claude", "codex"])
        #expect(NewSessionCommand(name: "Build", commandLine: "swift build && swift test").isValid)
        #expect(!NewSessionCommand(name: "", commandLine: "ls").isValid)
        #expect(!NewSessionCommand(name: String(repeating: "n", count: 51), commandLine: "ls").isValid)
        #expect(!NewSessionCommand(name: "Two", commandLine: "ls\nrm -rf ~").isValid)
        #expect(!NewSessionCommand(name: "Long", commandLine: String(repeating: "c", count: 1001)).isValid)
    }
}
