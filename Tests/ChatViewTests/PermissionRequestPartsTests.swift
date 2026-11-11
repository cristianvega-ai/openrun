import AgentConversation
import Testing

@testable import ChatView

/// A request shows what the user allows: the change itself, not only a name.
struct PermissionRequestPartsTests {
    func words(_ tool: String, _ input: [String: JSONValue]) -> PermissionRequestWords {
        PermissionRequestWords(PermissionRequestItem(request: PermissionRequest(identifier: "p", toolName: tool, input: .object(input))), agentName: "Claude Code")
    }

    @Test func aCommandShowsTheRestOfItsInputToo() {
        let request = words("Bash", ["command": .string("make"), "dangerouslyDisableSandbox": .bool(true)])
        #expect(request.parts == [.text("make"), .note("More input:"), .text("dangerouslyDisableSandbox: true")])
    }

    @Test func aToolThatTheViewDoesNotKnowShowsItsWholeInput() {
        let request = words("mcp__notes__write", ["title": .string("A"), "body": .string("B\u{3164}")])
        #expect(request.title == "Claude Code wants to use mcp__notes__write")
        #expect(request.parts == [.text("body: B⟨U+3164⟩\ntitle: A")])
    }
}
