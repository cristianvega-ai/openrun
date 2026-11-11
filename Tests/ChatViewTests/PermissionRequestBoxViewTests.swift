import AgentConversation
import AppKit
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

    func box(_ tool: String, _ input: [String: JSONValue]) -> PermissionRequestBoxView {
        let request = PermissionRequest(identifier: "p1", toolName: tool, input: .object(input))
        let box = PermissionRequestBoxView()
        box.show(PermissionRequestWords(PermissionRequestItem(request: request), agentName: "Claude Code"), agentName: "Claude Code",
                 isAnswered: false, palette: ChatPalette(appearance: .graphite))
        return box
    }

    @Test func aWriteShowsItsPathAndItsContentInFull() {
        let shown = box("Write", ["file_path": .string("/tmp/x.sh"), "content": .string("rm -rf /")]).partViews
        #expect((shown.first as? NSTextField)?.stringValue == "/tmp/x.sh")
        #expect((shown.last as? DetailBoxView)?.textView.string == "rm -rf /")
    }

    @Test func anEditShowsItsDiff() {
        let shown = box("Edit", ["file_path": .string("a"), "old_string": .string("x"), "new_string": .string("y")]).partViews
        #expect((shown.last as? DiffBoxView)?.linesView.contentHeight ?? 0 > 0)
    }

    @Test func aLongCommandSaysHowManyLinesItHas() {
        let command = (1...40).map { "echo \($0)" }.joined(separator: "\n")
        let shown = box("Bash", ["command": .string(command)]).partViews
        #expect((shown.first as? NSTextField)?.stringValue == "40 lines. Scroll in the box to read all of them.")
        #expect((shown.last as? DetailBoxView)?.textView.string == command)
    }

    @Test func aCutRequestCanOnlyBeDenied() {
        let content = String(repeating: "x", count: PermissionRequestWords.shownLimit + 1)
        let request = box("Write", ["file_path": .string("f"), "content": .string(content)])
        #expect(request.allowButton.isHidden)
        #expect(!request.denyButton.isHidden)
    }

    @Test func inASmallPaneTheWholeRequestFitsWithFourLinesOfItsText() throws {
        let command = (1...40).map { "echo \($0)" }.joined(separator: "\n")
        let request = PermissionRequest(identifier: "p1", toolName: "Bash", input: .object(["command": .string(command)]))
        let box = PermissionRequestBoxView()
        box.show(PermissionRequestWords(PermissionRequestItem(request: request), agentName: "Claude Code"), agentName: "Claude Code",
                 isAnswered: false, palette: ChatPalette(appearance: .graphite), viewportHeight: ChatViewController.minimumTranscriptHeight)
        let text = try #require(box.partViews.last as? DetailBoxView)
        let font = ChatPalette(appearance: .graphite).smallCodeFont
        #expect(text.height(forWidth: 300) >= 4 * (font.ascender - font.descender) + 2 * DetailBoxView.padding.height)
        #expect(box.height(forWidth: 300) <= ChatViewController.minimumTranscriptHeight - 18 - RowSpacing.bottom)
    }
}
