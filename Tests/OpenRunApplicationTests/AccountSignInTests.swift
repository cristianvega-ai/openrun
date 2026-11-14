import Testing
@testable import OpenRunApplication

@Suite struct AccountSignInTests {
    @Test func theLoginOfTheAgentRunsUnderTheFolderOfTheAccount() {
        let work = AccountSignIn(agent: "claude-code", program: "claude", folder: "/Users/me/.claude-work")
        #expect(work.commandLine == "env CLAUDE_CONFIG_DIR='/Users/me/.claude-work' 'claude' auth login")
        let codex = AccountSignIn(agent: "codex", program: "codex", folder: "/Users/me/Codex Home's")
        #expect(codex.commandLine == #"env CODEX_HOME='/Users/me/Codex Home'\''s' 'codex' login"#)
        // The login of the shell keeps the folder that the shell chooses.
        #expect(AccountSignIn(agent: "claude-code", program: "/opt/bin/claude", folder: nil).commandLine == "'/opt/bin/claude' auth login")
        #expect(AccountSignIn(agent: "later", program: "later", folder: nil).commandLine == nil)
    }
}
