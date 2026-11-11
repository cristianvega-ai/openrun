@testable import Settings
import Testing

@Suite struct SettingTextTests {
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
