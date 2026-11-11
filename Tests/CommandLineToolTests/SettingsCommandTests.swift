import SessionProtocol
import Testing
@testable import CommandLineTool

@Suite struct SettingsCommandTests {
    /// The mark of a protected setting is a third column. A backslash stays
    /// one, so that `settings set` takes the text back, and a control
    /// character cannot add a line or drive the terminal.
    @Test func eachSettingIsOneLineOfNameAndText() {
        let settings = [
            SettingSummary(name: "theme", text: "dark\\\u{1B}[2J\nx\ty", isProtected: false),
            SettingSummary(name: "new-session-commands", text: #"[{"command":["claude"]}]"#, isProtected: false),
            SettingSummary(name: "session-limit", text: "100", isProtected: true),
        ]
        #expect(SettingsCommand.lines(of: settings) == """
            theme\tdark\\\\u{1B}[2J\\nx\\ty
            new-session-commands\t[{"command":["claude"]}]
            session-limit\t100\tprotected

            """)
    }
}
