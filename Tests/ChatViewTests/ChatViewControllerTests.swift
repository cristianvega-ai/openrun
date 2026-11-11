import AgentConversation
import AppKit
import Testing

@testable import ChatView

@MainActor struct ChatViewControllerTests {
    let controller = ChatViewController(facts: ChatThreadFacts(threadIdentifier: "thread", title: "A thread", agentName: "Claude Code"))

    @Test func aTranscriptShowsAsRows() {
        controller.show(Transcript(events: [TestEvents.user("1", "Hello"), TestEvents.text("a", "Hi."), TestEvents.turnEnd()]))
        #expect(controller.transcriptView.rows.map(\.key) == ["user:1", "text:a#0"])
    }

    @Test func anUpdateShowsTheNewText() {
        controller.view.frame.size = NSSize(width: 600, height: 400)
        var transcript = Transcript(events: [TestEvents.user("1", "Hello"), TestEvents.delta("a", "One")])
        controller.show(transcript)
        controller.view.layoutSubtreeIfNeeded()
        let change = transcript.apply(TestEvents.delta("a", " two"))
        controller.update(transcript, change: change)
        #expect(controller.context.text(ofBlocks: 0..<1, in: "text:a").string == "One two")
        #expect(controller.transcriptView.rowViews.views.keys.sorted() == ["activity", "text:a#0", "user:1"])
    }

    @Test func aLinkGoesToTheHost() {
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        controller.openLink("https://example.com")
        #expect(delegate.requests == ["link https://example.com"])
    }

    @Test func aNewAppearanceKeepsTheRows() {
        controller.show(Transcript(events: [TestEvents.user("1", "Hello")]))
        controller.appearance = ChatAppearance(light: ChatAppearance.graphite.light, dark: ChatAppearance.graphite.dark, bodyFontSize: 16)
        #expect(controller.context.palette.bodyFont.pointSize == 16)
        #expect(controller.transcriptView.rows.count == 2)
    }

    @Test func anAnswerGoesToTheHost() {
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        controller.answerPermissionRequest("p1", with: .deny(message: "Not now"))
        #expect(delegate.requests == ["answer p1 deny(message: Optional(\"Not now\"))"])
    }

    @Test func earlierHistoryShowsARowAndLoadsOnce() {
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        controller.facts.hasEarlierHistory = true
        controller.show(Transcript(events: [TestEvents.user("1", "Hello")]))
        #expect(controller.transcriptView.rows.first?.key == "earlier")
        controller.loadEarlierHistory()
        controller.loadEarlierHistory()
        #expect(delegate.requests == ["earlier"])
        #expect(controller.context.isLoadingEarlierHistory)
    }

    @Test func theComposerSendsThroughTheHostAndKeepsADraft() {
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        controller.composer.textView.string = "Run the tests."
        controller.composer.submit()
        #expect(delegate.requests == ["send Run the tests. 0"])
        controller.composer.textView.string = "Half"
        controller.composer.textDidChange(Notification(name: NSText.didChangeNotification))
        controller.facts.threadIdentifier = "other"
        #expect(controller.composer.textView.string == "")
        controller.facts.threadIdentifier = "thread"
        #expect(controller.composer.textView.string == "Half")
        #expect(controller.focusView === controller.composer.textView)
        let image = MessageImage(mediaType: "image/png", data: Data([1]))
        controller.composer.images = [image]
        controller.facts.threadIdentifier = "other"
        #expect(controller.composer.images.isEmpty)
        controller.facts.threadIdentifier = "thread"
        #expect(controller.composer.images == [image])
        // The thread closes while the chat shows another one.
        controller.facts.threadIdentifier = "other"
        ChatViewController.forgetDraft(ofThread: "thread")
        controller.facts.threadIdentifier = "thread"
        #expect(controller.composer.draft.isEmpty)
    }

    @Test func theStateOfTheThreadShowsAroundTheTranscript() {
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        controller.show(Transcript())
        #expect(!controller.emptyView.isHidden)
        #expect(controller.conditionView.isHidden)
        controller.facts.accountName = "Work"
        controller.facts.condition = .openInTerminal
        #expect(controller.composer.isHidden && controller.terminalButton.isHidden && controller.emptyView.isHidden)
        #expect(controller.agentLabel.stringValue == "Claude Code · Work")
        controller.conditionView.buttons.first?.performClick(nil)
        controller.terminalButton.performClick(nil)
        #expect(delegate.requests == ["return", "terminal"])
    }

    @Test func atTheLimitTheComposerSaysSoAndTakesNoMessage() {
        let delegate = RecordingDelegate()
        controller.delegate = delegate
        controller.facts.condition = .atLimit(resetTime: nil, otherAccounts: [ChatAccount(identifier: "p", name: "Personal")])
        let field = controller.composer.textView
        #expect(!field.isEditable)
        #expect(field.placeholder == "The account is at its limit")
        field.string = "Go on."
        controller.composer.submit()
        #expect(delegate.requests.isEmpty)
        #expect(field.string == "Go on.")
        #expect(!controller.conditionView.buttons.isEmpty)
        controller.facts.condition = .ready
        #expect(field.isEditable)
        #expect(field.placeholder == "Message Claude Code")
    }

    @Test func aNewRequestIsAnnouncedOnceAlsoWhenItsRowHasNoView() {
        controller.view.frame.size = NSSize(width: 600, height: 400)
        var transcript = Transcript(events: (0..<80).map { TestEvents.user("\($0)", "Message \($0)") })
        controller.show(transcript)
        controller.view.layoutSubtreeIfNeeded()
        controller.scrollView.contentView.scroll(to: .zero)
        let request = transcript.apply(TestEvents.permission("p1", "Bash", ["command": "make"]))
        controller.update(transcript, change: request)
        #expect(controller.transcriptView.rowViews.views.values.allSatisfy { !($0 is PermissionRequestRowView) })
        #expect(controller.context.announcedRequests == ["p1"])
        let change = transcript.apply(TestEvents.permissionEnd("p1", .allowed))
        controller.update(transcript, change: change)
        #expect(controller.context.announcedRequests == ["p1"])
    }
}
