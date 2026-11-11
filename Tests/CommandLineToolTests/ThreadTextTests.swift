import AgentConversation
import Foundation
import Testing
@testable import CommandLineTool

@Suite struct ThreadTextTests {
    private func event(_ kind: ConversationEventKind) -> ConversationEvent { ConversationEvent(kind) }

    @Test func theConversationIsOneBlockForEachItem() {
        let events = [
            event(.userMessage(UserMessage(identifier: "u1", text: "List the files.\nThen stop.", imageCount: 2, isAccepted: true))),
            event(.agentText(AgentText(itemIdentifier: "m1", text: "Here they are."))),
            event(.notice(Notice(level: .information, text: "A notice."))),
            event(.turnEnded(TurnEnd(outcome: .failed, errorText: "No credit."))),
        ]
        #expect(ThreadText.text(of: events) == """
            You (with 2 images):
            List the files.
            Then stop.

            Agent:
            Here they are.

            Notice: A notice.

            The turn failed: No credit.

            """)
        #expect(ThreadText.text(of: []) == "")
        #expect(ThreadText.block(of: .turnEnd(TurnEnd(outcome: .done))) == nil)
        #expect(ThreadText.block(of: .turnEnd(TurnEnd(outcome: .stopped))) == "The turn stopped.")
    }
}
