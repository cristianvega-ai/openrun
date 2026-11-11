import AgentConversation
import Testing

@testable import ChatView

struct PermissionRequestWordsTests {
    func item(_ tool: String, _ input: [String: String]) -> PermissionRequestItem {
        PermissionRequestItem(request: PermissionRequest(identifier: "p1", toolName: tool, input: TestEvents.object(input)))
    }

    @Test func aCommandShowsInFullWithItsHiddenCharactersMarked() {
        let words = PermissionRequestWords(item("Bash", ["command": "echo a\u{202E}b\rc\n\tls\u{1B}"]), agentName: "Claude Code")
        #expect(words.title == "Claude Code wants to run a command")
        #expect(words.subject == "echo a⟨U+202E⟩b⏎c\n\tls⎋")
    }

    @Test func anotherToolShowsItsInputAndTheAnswer() {
        let words = PermissionRequestWords(item("mcp__notes__write", ["title": "A", "body": "B"]), agentName: "Codex")
        #expect(words.title == "Codex wants to use mcp__notes__write")
        #expect(words.subject == "body: B\ntitle: A")
    }

    @Test func aVeryLongCommandKeepsItsStartAndItsEnd() {
        let shown = PermissionRequestWords.bounded(String(repeating: "a", count: 5_000) + "END")
        #expect(shown.hasPrefix("aaa") && shown.hasSuffix("END"))
        #expect(shown.contains("1003 characters not shown"))
    }
}
