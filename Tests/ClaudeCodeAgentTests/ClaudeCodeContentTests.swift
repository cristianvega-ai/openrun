import AgentConversation
import Foundation
import Testing
@testable import ClaudeCodeAgent

@Suite struct ClaudeCodeContentTests {
    func json(_ text: String) throws -> JSONValue {
        try JSONValue(decoding: Data(text.utf8))
    }

    @Test func eachKnownBlockOfTheAgentGivesItsEvent() throws {
        #expect(ClaudeCodeContent.assistantEvent(try json(#"{"type":"text","text":"ok"}"#), itemIdentifier: "m:0")
            == .agentText(AgentText(itemIdentifier: "m:0", text: "ok")))
        #expect(ClaudeCodeContent.assistantEvent(try json(#"{"type":"thinking","thinking":"","signature":"x"}"#), itemIdentifier: "m:1")
            == .thinking(Thinking(itemIdentifier: "m:1", isComplete: true)))
        #expect(ClaudeCodeContent.assistantEvent(try json(#"{"type":"tool_use","id":"t","name":"Bash","input":{"command":"ls"}}"#), itemIdentifier: "m:2")
            == .toolCallInput(ToolCallInput(identifier: "t", name: "Bash", input: .object(["command": .string("ls")]))))
        #expect(ClaudeCodeContent.assistantEvent(try json(#"{"type":"server_tool_use","id":"s"}"#), itemIdentifier: "m:3") == nil)
    }

    @Test func aToolResultWithThePatchOfAnEditGivesAFileChange() throws {
        let block = try json(#"{"tool_use_id":"t","type":"tool_result","content":[{"type":"text","text":"Done"},{"type":"image"}]}"#)
        let details = try json(#"""
            {"filePath":"/work/project/notes.txt","oldString":"hi","newString":"hello",
             "structuredPatch":[{"oldStart":1,"oldLines":1,"newStart":1,"newLines":1,"lines":["-hi","+hello"]}]}
            """#)
        #expect(ClaudeCodeContent.toolResultEvents(block, details: details) == [
            .toolCallResult(ToolCallResult(identifier: "t", output: "Done\n[image]", isError: false)),
            .fileChange(FileChange(identifier: "t", toolCallIdentifier: "t", path: "/work/project/notes.txt",
                                   kind: .modified, diff: "@@ -1,1 +1,1 @@\n-hi\n+hello")),
        ])
    }

    @Test func aNewFileGivesAnAddedFileWithEachLine() throws {
        let details = try json(#"{"type":"create","filePath":"/work/project/a.txt","content":"one\ntwo\n","structuredPatch":[]}"#)
        #expect(ClaudeCodeContent.fileChange(toolCallIdentifier: "t", details: details) == FileChange(
            identifier: "t", toolCallIdentifier: "t", path: "/work/project/a.txt", kind: .added, diff: "@@ -0,0 +1,2 @@\n+one\n+two"))
        #expect(ClaudeCodeContent.fileChange(toolCallIdentifier: "t", details: try json(#"{"stdout":"hi"}"#)) == nil)
        #expect(ClaudeCodeContent.fileChange(toolCallIdentifier: "t", details: .string("User rejected tool use")) == nil)
    }

    @Test func theTextOfContentJoinsItsTextBlocks() throws {
        #expect(ClaudeCodeContent.text(of: .string("Hi")) == "Hi")
        #expect(ClaudeCodeContent.text(of: try json(#"[{"type":"text","text":"a"},{"type":"text","text":"b"}]"#)) == "a\nb")
        #expect(ClaudeCodeContent.imageCount(of: try json(#"[{"type":"text","text":"a"},{"type":"image"}]"#)) == 1)
        #expect(ClaudeCodeContent.text(of: .null) == "")
    }
}
