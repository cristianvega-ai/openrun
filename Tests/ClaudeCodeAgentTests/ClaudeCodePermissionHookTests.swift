import AgentConversation
import ClaudeCodeAgent
import Foundation
import Testing

@Suite struct ClaudeCodePermissionHookTests {
    @Test func theRecordedRequestGivesTheToolAndItsInput() throws {
        let data = try Data(contentsOf: Fixture.folder.appending(path: "permission-request.json"))
        let request = try ClaudeCodePermissionHookRequest(decoding: data)
        #expect(request.conversationIdentifier == "00000000-0000-4000-8000-000000000003")
        #expect(request.transcriptPath == "/config/claude/projects/-work-project/00000000-0000-4000-8000-000000000003.jsonl")
        #expect(request.workingFolder == "/work/project")
        #expect(request.permissionMode == "default")
        #expect(request.toolName == "Bash")
        let input = JSONValue.object([
            "command": .string("touch approved.txt"), "description": .string("Create empty approved.txt file with touch"),
        ])
        #expect(request.toolInput == input)
        #expect(request.permissionRequest(identifier: "p1", toolCallIdentifier: "t1")
            == PermissionRequest(identifier: "p1", toolName: "Bash", input: input, toolCallIdentifier: "t1"))
    }

    @Test func inputThatIsNotAPermissionRequestIsRefused() {
        for text in ["", "noise", "[]", #"{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash"}"#,
                     #"{"hook_event_name":"PermissionRequest","session_id":"s"}"#] {
            #expect(throws: ClaudeCodePermissionHookError.invalidRequest) {
                try ClaudeCodePermissionHookRequest(decoding: Data(text.utf8))
            }
        }
    }

    @Test func theAnswersAreTheJSONThatClaudeCodeReads() {
        #expect(String(decoding: ClaudeCodePermissionHookAnswer.allow.output, as: UTF8.self)
            == #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"# + "\n")
        #expect(String(decoding: ClaudeCodePermissionHookAnswer.deny(message: "Use \"echo\" / not touch.\n").output, as: UTF8.self)
            == #"{"hookSpecificOutput":{"decision":{"behavior":"deny","message":"Use \"echo\" / not touch.\n"},"hookEventName":"PermissionRequest"}}"# + "\n")
    }
}
