import AgentConversation
import Testing

@testable import ChatView

@MainActor struct PermissionRequestRowViewTests {
    final class Actions: TranscriptRowActions {
        var answers: [String] = []
        func openLink(_ target: String) {}
        func toggle(_ part: String, in row: TranscriptRowView) {}
        func answerPermissionRequest(_ identifier: String, with answer: ChatPermissionAnswer) { answers.append(identifier) }
    }

    @Test func aWaitingRequestAnswersOnceAndThenFolds() {
        let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))
        let actions = Actions()
        context.actions = actions
        var events = [TestEvents.permission("p1", "Bash", ["command": "ls"])]
        context.transcript = Transcript(events: events)
        let row = TranscriptRow(key: "permission:p1", kind: .permissionRequest(item: "permission:p1"))
        let view = PermissionRequestRowView()
        view.configure(row, context: context)
        #expect(view.parts.first?.view === view.box)
        view.box.allow()
        view.box.allow()
        #expect(actions.answers == ["p1"])
        events.append(TestEvents.permissionEnd("p1", .denied, message: "No"))
        context.transcript = Transcript(events: events)
        view.configure(row, context: context)
        #expect(view.parts.first?.view === view.foldedLine)
        #expect(view.foldedLine.title.stringValue == "Denied: ls")
        #expect(view.foldedLine.status.stringValue == "“No”")
    }
}
