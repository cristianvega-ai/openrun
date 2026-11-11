import AgentConversation
import Testing

@testable import ChatView

@MainActor struct PermissionRequestBoxViewTests {
    @Test func denyCarriesTheMessageAndAnAnswerTurnsTheButtonsOff() {
        let box = PermissionRequestBoxView()
        let request = PermissionRequest(identifier: "p1", toolName: "Bash", input: TestEvents.object(["command": "ls"]))
        let words = PermissionRequestWords(PermissionRequestItem(request: request), agentName: "Claude Code")
        box.show(words, agentName: "Claude Code", isAnswered: false, palette: ChatPalette(appearance: .graphite))
        var answers: [ChatPermissionAnswer] = []
        box.answerAction = { answers.append($0) }
        box.messageField.stringValue = "  Run the tests first. "
        box.deny()
        box.allow()
        #expect(answers == [.deny(message: "Run the tests first."), .allow])
        #expect(box.height(forWidth: 360) > box.height(forWidth: 700) - 1)
        box.show(words, agentName: "Claude Code", isAnswered: true, palette: ChatPalette(appearance: .graphite))
        #expect(!box.allowButton.isEnabled && !box.denyButton.isEnabled)
    }
}
