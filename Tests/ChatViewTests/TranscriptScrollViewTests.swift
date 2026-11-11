import AgentConversation
import AppKit
import Testing

@testable import ChatView

@MainActor struct TranscriptScrollViewTests {
    let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
    let scrollView: TranscriptScrollView

    init() {
        scrollView = TranscriptScrollView(transcriptView: TranscriptView(context: context))
        scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        show(messages: 60)
    }

    func show(messages count: Int) {
        context.transcript = Transcript(events: (0..<count).map { TestEvents.user("\($0)", "Message \($0)") })
        let rows = (0..<count).map { TranscriptRow(key: "user:\($0)", kind: .userMessage(item: "user:\($0)")) }
        scrollView.transcriptView.setRows(rows, changed: [])
    }

    @Test func theViewFollowsTheNewestRow() {
        #expect(scrollView.distanceFromBottom == 0)
        show(messages: 61)
        #expect(scrollView.distanceFromBottom == 0)
        #expect(scrollView.transcriptView.rowViews.views["user:60"] != nil)
    }

    @Test func aScrollUpStopsTheFollowAndNewRowsDoNotMoveTheScreen() {
        var changes: [Bool] = []
        scrollView.followingChanged = { changes.append($0) }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 500))
        #expect(!scrollView.transcriptView.isFollowingBottom)
        let origin = scrollView.contentView.bounds.minY
        show(messages: 70)
        #expect(scrollView.contentView.bounds.minY == origin)
        scrollView.scrollToNewest()
        #expect(scrollView.distanceFromBottom == 0)
        #expect(changes == [false, true])
    }

    @Test func aRowThatOpensKeepsItsPlaceOnTheScreen() {
        let index = 55
        func top() -> CGFloat? {
            scrollView.transcriptView.rowViews.views["user:\(index)"].map { $0.frame.minY - scrollView.contentView.bounds.minY }
        }
        let before = top()
        let long = String(repeating: "A longer message. ", count: 40)
        context.transcript = Transcript(events: (0..<60).map { TestEvents.user("\($0)", $0 == index ? long : "Message \($0)") })
        scrollView.keepInPlace("user:\(index)")
        #expect(before != nil && top() == before)
        #expect(!scrollView.transcriptView.isFollowingBottom)
    }

    @Test func aNewSizeIsNoScrollOfTheUser() {
        scrollView.frame.size = NSSize(width: 360, height: 300)
        scrollView.layoutSubtreeIfNeeded()
        #expect(scrollView.transcriptView.isFollowingBottom)
        #expect(scrollView.distanceFromBottom == 0)
    }

    @Test func aRevealedRowStandsAThirdDownTheScreen() {
        let view = scrollView.reveal("user:10")
        #expect(view?.searchableTextView?.string == "Message 10")
        #expect(!scrollView.transcriptView.isFollowingBottom)
        #expect(scrollView.reveal("user:none") == nil)
    }
}
