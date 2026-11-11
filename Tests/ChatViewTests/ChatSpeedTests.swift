import AgentConversation
import AppKit
import Testing

@testable import ChatView

/// The chat must keep up with an agent that writes fast, in a long thread.
/// The tests drive time themselves, so they need no display.
@MainActor @Suite(.serialized) struct ChatSpeedTests {
    let controller = ChatViewController(facts: ChatThreadFacts(threadIdentifier: "speed", title: "Speed", agentName: "Claude Code"))
    let clock = ContinuousClock()

    /// A thread of `count` items: questions, answers and commands.
    static func events(items count: Int) -> [ConversationEvent] {
        // A call and its result make one item.
        (0..<count / 3).flatMap { index in
            [
                TestEvents.user("\(index)", "Question \(index): why does the build fail?"),
                TestEvents.tool("b\(index)", "Bash", ["command": "swift build --target Module\(index)"]),
                TestEvents.result("b\(index)", "Build complete!"),
                TestEvents.text("a\(index)", "The answer \(index) has **bold** text, `code`, and a [link](https://example.com)."),
            ]
        }
    }

    /// A window that is never on the screen, so the chat draws only what changed.
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)

    func show(_ transcript: Transcript, width: CGFloat = 820) {
        window.contentView = controller.view
        controller.view.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        controller.show(transcript)
        drawFrame()
    }

    /// Lays out and draws what changed, as for a frame of the screen.
    func drawFrame() {
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()
    }

    @Test func sixtyUpdatesOfAStreamFitInASecondOnTwoThousandItems() {
        var transcript = Transcript(events: Self.events(items: 2_000) + [TestEvents.user("last", "One more.")])
        show(transcript)
        let elapsed = clock.measure {
            for index in 0..<60 {
                let change = transcript.apply(TestEvents.delta("streaming", "Word \(index) of a **long** answer. "))
                controller.update(transcript, change: change)
                drawFrame()
            }
        }
        print("An update and a frame on 2,000 items took \(elapsed / 60).")
        #expect(controller.scrollView.distanceFromBottom == 0)
        #expect(elapsed < .seconds(1))
    }

    @Test func tenThousandItemsShowQuickly() {
        let transcript = Transcript(events: Self.events(items: 10_002), limits: TranscriptLimits(itemLimit: 20_000, byteLimit: 1 << 30))
        let elapsed = clock.measure {
            show(transcript)
            drawFrame()
        }
        print("The first show of \(transcript.items.count) items took \(elapsed).")
        #expect(transcript.items.count == 10_002)
        #expect(controller.transcriptView.rowViews.views.count < 60)
        #expect(elapsed < .seconds(2))
    }

    @Test func anOutputOfTenThousandLinesOpensQuickly() throws {
        let output = (1...10_000).map { "line \($0) of the output of the test" }.joined(separator: "\n")
        show(Transcript(events: [
            TestEvents.user("1", "Run the tests."), TestEvents.tool("big", "Bash", ["command": "swift test"]),
            TestEvents.result("big", output), TestEvents.turnEnd(),
        ]))
        let row = try #require(controller.transcriptView.rowViews.views["group:tool:big"])
        let elapsed = clock.measure {
            controller.toggle("tool:big", in: row)
            drawFrame()
        }
        print("The open of an output of 10,000 lines took \(elapsed).")
        #expect(controller.context.openedParts == ["tool:big"])
        #expect(elapsed < .milliseconds(100))
    }

    @Test func aResizeOfTwoThousandItemsKeepsUp() {
        show(Transcript(events: Self.events(items: 2_000)))
        let elapsed = clock.measure {
            for width in stride(from: 820, to: 580, by: -8) {
                controller.view.frame.size.width = CGFloat(width)
                drawFrame()
            }
        }
        print("A step of a resize on 2,000 items took \(elapsed / 30).")
        #expect(controller.scrollView.distanceFromBottom == 0)
        #expect(elapsed / 30 < .milliseconds(16))
    }
}
