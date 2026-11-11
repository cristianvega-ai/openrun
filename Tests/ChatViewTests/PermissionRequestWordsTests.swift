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

    @Test func charactersThatDrawAsBlankShowAsCodes() {
        // Fillers, a blank Braille cell, spaces that are not a space, tags,
        // a variation selector on its own, and zero-width characters.
        let hidden: [UInt32] = [0x3164, 0x115F, 0xFFA0, 0x2800, 0x00A0, 0x2003, 0x3000, 0xE0041, 0xFE0F, 0x200B, 0x2060, 0x034F]
        for value in hidden {
            let scalar = Character(Unicode.Scalar(value)!)
            #expect(PermissionRequestWords.visible("a\(scalar)b") == "a⟨U+\(String(format: "%04X", value))⟩b")
        }
    }

    @Test func anEmojiKeepsItsVariationSelector() {
        #expect(PermissionRequestWords.visible("echo \u{2764}\u{FE0F}") == "echo \u{2764}\u{FE0F}")
    }
}
