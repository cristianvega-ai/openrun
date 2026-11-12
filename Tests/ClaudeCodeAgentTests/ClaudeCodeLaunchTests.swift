import Foundation
import Testing
import ClaudeCodeAgent

@Suite struct ClaudeCodeLaunchTests {
    let identifier = UUID(uuidString: "00000000-0000-4000-8000-00000000C0DE")!
    let settings = #"{"hooks":{"PermissionRequest":[{"hooks":[{"args":["permission-request"],"command":"/Applications/OpenRun.app/Contents/Helpers/openrun","onFailure":"block","timeout":86400,"type":"command"}],"matcher":"*"}]}}"#

    func launch(_ conversation: ClaudeCodeLaunch.Conversation) throws -> ClaudeCodeLaunch {
        try ClaudeCodeLaunch(
            model: "haiku", permissionMode: .standard, conversation: conversation,
            hookCommand: "/Applications/OpenRun.app/Contents/Helpers/openrun", hookArguments: ["permission-request"])
    }

    @Test func aNewConversationGetsTheWholeCommandLineAndItsIdentifier() throws {
        #expect(try launch(.new(identifier)).arguments == [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--include-partial-messages", "--replay-user-messages", "--model", "haiku", "--permission-mode", "default",
            "--permission-prompts", "none", "--settings", settings, "--session-id", "00000000-0000-4000-8000-00000000c0de",
        ])
    }

    @Test func aLaterStartResumesTheConversation() throws {
        #expect(try launch(.resume(identifier)).arguments.suffix(2) == ["--resume", "00000000-0000-4000-8000-00000000c0de"])
    }

    /// Open in Terminal runs Claude Code itself, with no headless flag and no hook.
    @Test func theTerminalGetsTheConversationTheModelAndTheMode() throws {
        let text = identifier.uuidString.lowercased()
        #expect(try launch(.resume(identifier)).terminalArguments == ["--resume", text, "--model", "haiku", "--permission-mode", "default"])
        #expect(try launch(.new(identifier)).terminalArguments.prefix(2) == ["--session-id", text])
    }

    @Test func noModeSkipsEveryCheck() {
        #expect(!ClaudeCodePermissionMode.allCases.map(\.rawValue).contains("bypassPermissions"))
        #expect(ClaudeCodePermissionMode.allCases.map(\.rawValue) == ["default", "acceptEdits", "plan", "dontAsk", "auto"])
    }

    @Test func aModelNameThatCouldPassForAFlagIsRefused() {
        for model in ["", "--dangerously-skip-permissions", "haiku sonnet", "haiku\n", "é"] {
            #expect(throws: ClaudeCodeLaunchError.invalidModel) {
                try ClaudeCodeLaunch(model: model, permissionMode: .plan, conversation: .new(UUID()), hookCommand: "/h", hookArguments: [])
            }
        }
        #expect((try? ClaudeCodeLaunch(model: "claude-opus-5-5[1m]", permissionMode: .plan, conversation: .new(UUID()), hookCommand: "/h", hookArguments: [])) != nil)
    }

    @Test func theEnvironmentLosesTheMarksOfANestedRunAndKeepsTheAccount() {
        let base = ["PATH": "/usr/bin", "HOME": "/Users/example", "CLAUDE_CONFIG_DIR": "/config/claude", "CLAUDECODE": "1",
                    "CLAUDE_CODE_ENTRYPOINT": "cli", "CLAUDE_CODE_MESSAGING_SOCKET": "/tmp/s", "AI_AGENT": "claude", "OTHER": "a"]
        #expect(ClaudeCodeEnvironment.make(base: base, additions: ["OTHER": "b", "OPENRUN_THREAD": "t"]) == [
            "PATH": "/usr/bin", "HOME": "/Users/example", "CLAUDE_CONFIG_DIR": "/config/claude", "OTHER": "b", "OPENRUN_THREAD": "t",
        ])
    }
}
