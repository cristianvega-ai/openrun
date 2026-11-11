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
        composer.sendAction = { sent.append($0.text) }
        composer.setBusy(true)
        composer.textView.string = "Then commit."
        composer.submit()
        #expect(sent.isEmpty)
        #expect(composer.textView.string.isEmpty)
        #expect(!composer.heldView.isHidden)
        #expect(composer.heldView.text.stringValue == "Then commit.")
        #expect(composer.noteButton.isHidden)
        composer.setBusy(false)
        #expect(sent == ["Then commit."])
        #expect(composer.heldView.isHidden)
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

    @Test func aHeldMessageCanBeEditedOrDeleted() {
        composer.setBusy(true)
        composer.textView.string = "First"
        composer.submit()
        composer.heldView.editButton.performClick(nil)
        #expect(composer.textView.string == "First")
        #expect(composer.heldView.isHidden)
        composer.submit()
        composer.heldView.deleteButton.performClick(nil)
        #expect(composer.logic.heldMessage == nil)
        #expect(composer.textView.string.isEmpty)
    }

    @Test func aStopPutsTheHeldMessageBackInTheField() {
        var sent: [String] = []
        var stops = 0
        composer.sendAction = { sent.append($0.text) }
        composer.stopAction = { stops += 1 }
        composer.setBusy(true)
        composer.textView.string = "Then commit."
        composer.submit()
        composer.sendOrStop()
        #expect(stops == 1)
        #expect(composer.textView.string == "Then commit.")
        composer.setBusy(false)
        #expect(sent.isEmpty)
    }

    @Test func commandPeriodOnAnIdleThreadStopsNothing() {
        var stops = 0
        composer.stopAction = { stops += 1 }
        composer.textView.stopAction?(true)
        composer.textView.stopAction?(false)
        composer.textView.stopAction?(false)
        #expect(stops == 0)
    }

    @Test func imagesGoWithTheMessageAndAHeldMessageComesBack() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        composer.textView.imagesAction?([png, Data("text".utf8)])
        #expect(composer.images.count == 1)
        #expect(composer.problem == ComposerImage.Problem.unknownType.message)
        composer.previews.removeAction?(0)
        #expect(composer.images.isEmpty)
        composer.setBusy(true)
        composer.textView.string = "Wait"
        composer.submit()
        composer.takeHeldMessage()
        #expect(composer.textView.string == "Wait")
        #expect(composer.logic.heldMessage == nil)
    }
}
