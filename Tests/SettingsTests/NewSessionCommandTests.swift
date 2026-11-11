@testable import Settings
import Testing

@Suite struct NewSessionCommandTests {
    @Test func aCommandNeedsANameAndAPlainCommandLine() {
        #expect(NewSessionCommand.defaults.allSatisfy { $0.isValid })
        #expect(NewSessionCommand.defaults.map(\.commandLine) == ["", "claude", "codex"])
        #expect(NewSessionCommand(name: "Build", commandLine: "swift build && swift test").isValid)
        #expect(!NewSessionCommand(name: "", commandLine: "ls").isValid)
        #expect(!NewSessionCommand(name: String(repeating: "n", count: 51), commandLine: "ls").isValid)
        #expect(!NewSessionCommand(name: "Two", commandLine: "ls\nrm -rf ~").isValid)
        #expect(!NewSessionCommand(name: "Long", commandLine: String(repeating: "c", count: 1001)).isValid)
    }

    @Test func aNameOrCommandThatChangesTheDirectionIsRefused() {
        #expect(!NewSessionCommand(name: "a\u{202E}b", commandLine: "ls").isValid)
        #expect(!NewSessionCommand(name: "Build", commandLine: "ls \u{2066}x\u{2069}").isValid)
        #expect(SettingTextForm.value(of: "dusk\u{200F}", as: SettingName.theme.kind) == nil)
        #expect(SettingTextForm.value(of: "Menlo\u{061C}", as: SettingName.fontName.kind) == nil)
        #expect(SettingTextForm.value(of: "👩‍💻 Mono", as: SettingName.fontName.kind) == .text("👩‍💻 Mono"))
    }
}
