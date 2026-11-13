import AgentConversation
import AppKit
import Testing
@testable import ChatView

/// An answer that did not reach the thread is not lost
/// (finding 11 of the state machine audit).
@MainActor @Suite struct ChatRequestFailureTests {
    @Test func failedPermissionAnswerCanBeRetried() {
        let controller = ChatViewController(facts: ChatThreadFacts(threadIdentifier: "t", title: "T", agentName: "Agent"))
        controller.context.answeredRequests = ["first", "second"]
        controller.retryPermissionAnswer("first")
        #expect(controller.context.answeredRequests == ["second"])
    }
}
