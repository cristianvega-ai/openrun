import AppKit
import Testing

@testable import ChatView

@MainActor struct ComposerViewTests {
    let composer = ComposerView(palette: ChatPalette(appearance: .graphite))

    @Test func theFieldGrowsWithItsText() {
        composer.noteButton.isHidden = true
        composer.textView.font = composer.palette.bodyFont
        let empty = composer.height(forWidth: 600)
        composer.textView.string = "One\nTwo\nThree"
        #expect(composer.height(forWidth: 600) > empty + 30)
        composer.frame = NSRect(x: 0, y: 0, width: 600, height: composer.height(forWidth: 600))
        composer.layout()
        #expect(composer.scrollView.frame.height == composer.composerLayout(forWidth: 600).field.height)
    }

    @Test func theComposerShowsTheFactsAndAProblem() {
        composer.show(ChatThreadFacts(threadIdentifier: "t", title: "T", agentName: "Codex"), palette: composer.palette)
        #expect(composer.textView.placeholder == "Message Codex")
        #expect(composer.noteButton.isHidden)
        #expect(composer.sendButton.accessibilityLabel() == "Send")
        composer.problem = "The image is too large."
        composer.refresh()
        #expect(!composer.noteButton.isHidden)
        #expect(composer.noteButton.title == "The image is too large.")
    }

    @Test func aMessageWrittenWhileTheAgentWorksGoesAtTheEnd() {
        var sent: [String] = []
        var stops = 0
        composer.sendAction = { sent.append($0.text) }
        composer.stopAction = { stops += 1 }
        composer.setBusy(true)
        composer.textView.string = "Then commit."
        composer.submit()
        #expect(sent.isEmpty)
        #expect(composer.textView.string.isEmpty)
        #expect(!composer.noteButton.isHidden)
        composer.sendOrStop()
        #expect(stops == 1)
        composer.setBusy(false)
        #expect(sent == ["Then commit."])
        #expect(composer.noteButton.isHidden)
    }

    @Test func escapeTwiceStopsAndCommandPeriodStopsAtOnce() {
        var stops = 0
        composer.stopAction = { stops += 1 }
        composer.setBusy(true)
        composer.textView.stopAction?(false)
        #expect(stops == 0)
        composer.textView.stopAction?(false)
        #expect(stops == 1)
        composer.textView.stopAction?(true)
        #expect(stops == 2)
    }
}
