import AgentConversation
import Testing

@testable import ChatView

struct ToolCallSummaryTests {
    func call(_ name: String, _ input: [String: String], state: ToolCallItem.State = .succeeded) -> ToolCallItem {
        var call = ToolCallItem(name: name, state: state)
        call.input = TestEvents.object(input)
        return call
    }

    @Test func eachToolHasItsOwnWords() {
        #expect(ToolCallSummary(call("Read", ["file_path": "/work/Sources/Transcript.swift"])).title == "Read Transcript.swift")
        let command = ToolCallSummary(call("Bash", ["command": "swift build\nswift test"]))
        #expect(command.title == "Ran swift build")
        #expect(command.subject == "swift build\nswift test")
        #expect(ToolCallSummary(call("Bash", ["command": "ls", "description": "List the files"])).title == "List the files")
        #expect(ToolCallSummary(call("Grep", ["pattern": "removed"])).title == "Searched for “removed”")
        #expect(ToolCallSummary(call("mcp__notes__find", [:])).title == "mcp__notes__find")
    }

    @Test func aCallThatDidNotSucceedSaysWhy() {
        var failed = call("Bash", ["command": "false"], state: .failed)
        failed.exitCode = 1
        #expect(ToolCallSummary(failed).status == "Exit code 1")
        #expect(ToolCallSummary(call("Read", [:], state: .running)).status == "Running")
        #expect(ToolCallSummary(call("Read", [:])).status == nil)
    }

    @Test func aRunOfCallsCountsEachKind() {
        let calls = [call("Read", [:]), call("Read", [:]), call("Grep", [:]), call("Glob", [:]), call("Bash", [:])]
        #expect(ToolCallSummary.title(ofRun: calls) == "Read 2 files, searched 2 times, ran 1 command")
    }

    @Test func theDetailShowsTheInputAndTheStartOfTheOutput() {
        var output = call("Bash", ["command": "seq 20"])
        output.output = (1...20).map(String.init).joined(separator: "\n")
        output.outputByteCount = output.output.utf8.count + 100
        let detail = ToolCallSummary.detail(of: output, subject: "seq 20")
        #expect(detail.map(\.text) == ["seq 20", (1...12).map(String.init).joined(separator: "\n")])
        #expect(detail.map(\.note) == [nil, "8 more lines and more output"])
    }
}
