import AgentConversation
import Foundation
import SessionProtocol
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

    @Test func textOfTheAgentCannotDriveTheTerminal() {
        let message = AgentMessage(text: "one\u{1B}]0;title\u{07}\ntwo\rthree \\n", isComplete: true)
        #expect(ThreadText.block(of: .agentMessage(message)) == "Agent:\none\\u{1B}]0;title\\u{7}\ntwo\\rthree \\n")
        #expect(ThreadText.block(of: .notice(Notice(level: .warning, text: "a\nb"))) == "Notice: a\\nb")
        let long = ThreadText.block(of: .notice(Notice(level: .warning, text: String(repeating: "x", count: 600))))
        #expect(long?.count == "Notice: ".count + 501 && long?.hasSuffix("…") == true)
    }

    @Test func aTypedStartFindsOneThread() throws {
        func thread(_ identifier: String, _ title: String) -> ThreadSummary {
            ThreadSummary(identifier: UUID(uuidString: identifier)!, agent: "claude-code", folder: "/work", model: "opus", permissionMode: "default",
                          title: title, createdAt: Date(timeIntervalSince1970: 0), lastActivityAt: Date(timeIntervalSince1970: 0))
        }
        let threads = [thread("AAAA0000-0000-4000-8000-000000000001", "One"), thread("AAAB0000-0000-4000-8000-000000000002", "Two")]
        #expect(try ThreadMatch.find("AAAB", in: threads).title == "Two")
        #expect(try ThreadMatch.find("aaaa0000-0000-4000-8000-000000000001", in: threads).title == "One")
        let failure = { (typed: String) -> String? in
            do { _ = try ThreadMatch.find(typed, in: threads) } catch { return "\(error)" }
            return nil
        }
        #expect(failure("b") == "No thread has an identifier that starts with b. Run 'openrun thread list' to see the threads.")
        #expect(failure("aaa") == """
            More than one thread starts with aaa. Type more characters.
              aaaa0000-0000-4000-8000-000000000001  One
              aaab0000-0000-4000-8000-000000000002  Two
            """)
    }
}
