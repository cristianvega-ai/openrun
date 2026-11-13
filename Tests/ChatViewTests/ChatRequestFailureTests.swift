import AgentConversation
import AppKit
import Testing
@testable import ChatView

/// A message or an answer that did not reach the thread is not lost
/// (finding 11 of the state machine audit).
@MainActor @Suite struct ChatRequestFailureTests {
    @Test func failedMessageRestoresAheadOfTheCurrentDraft() {
        let identifier = "restore-message-test"
        ComposerDrafts.shared.save(.init(text: "new draft"), for: identifier)
        ChatViewController.restoreFailedMessage(ChatOutgoingMessage(text: "failed"), ofThread: identifier)
        #expect(ComposerDrafts.shared.draft(for: identifier).text == "failed\n\nnew draft" && ComposerDrafts.shared.draft(for: identifier).isSubmitted)
        ComposerDrafts.shared.forget(identifier)
        // Other drafts do not take the room of a failed message. A store of its own leaves the other tests alone.
        var drafts = ComposerDrafts()
        drafts.save(.init(text: "failed", isSubmitted: true), for: identifier)
        for index in 0...ComposerDrafts.countLimit { drafts.save(.init(text: "other"), for: "other-\(index)") }
        #expect(drafts.draft(for: identifier).text == "failed")
    }

    @Test func failedPermissionAnswerCanBeRetried() {
        let controller = ChatViewController(facts: ChatThreadFacts(threadIdentifier: "t", title: "T", agentName: "Agent"))
        controller.context.answeredRequests = ["first", "second"]
        controller.retryPermissionAnswer("first")
        #expect(controller.context.answeredRequests == ["second"])
    }
}
