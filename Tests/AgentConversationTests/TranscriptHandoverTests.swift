@testable import AgentConversation
import Testing

@Suite struct TranscriptHandoverTests {
    private func user(_ identifier: String, _ text: String) -> ConversationEvent {
        ConversationEvent(.userMessage(UserMessage(identifier: identifier, text: text, isAccepted: true)))
    }

    private func agent(_ identifier: String, _ text: String) -> ConversationEvent {
        ConversationEvent(.agentText(AgentText(itemIdentifier: identifier, text: text)))
    }

    private var transcript: Transcript {
        let change = ConversationEvent(.fileChange(FileChange(identifier: "c1", path: "/work/a.swift", kind: .modified, diff: "+ line")))
        let call = ConversationEvent(.toolCallInput(ToolCallInput(identifier: "t1", name: "Bash", input: .object([:]))))
        return Transcript(events: [
            user("u1", "Repair the test."), call, agent("m1", "I changed the file."), change, ConversationEvent(.turnEnded(TurnEnd(outcome: .done))),
            user("u2", "Run it again."),
        ])
    }

    @Test func theMessageHoldsTheWordsOfTheUserAndTheAgentAndTheChangedFiles() {
        #expect(TranscriptHandover.message(from: transcript) == """
            Go on with the work of this earlier conversation. Its account reached the usage limit.

            User:
            Repair the test.

            Agent:
            I changed the file.

            The agent modified the file /work/a.swift.

            User:
            Run it again.
            """)
        #expect(TranscriptHandover.message(from: Transcript()) == nil)
    }

    @Test func aLongConversationKeepsItsNewestPart() throws {
        let short = try #require(TranscriptHandover.message(from: transcript, characterLimit: 70))
        #expect(short.hasPrefix(TranscriptHandover.opening + "\n\n" + TranscriptHandover.cutNotice + "\n\nThe agent modified"))
        #expect(short.hasSuffix("User:\nRun it again.") && !short.contains("Repair the test."))
        // One block alone that is past the limit keeps its end.
        let end = try #require(TranscriptHandover.message(from: Transcript(events: [user("u1", "abcdefghij")]), characterLimit: 4))
        #expect(end.hasSuffix(TranscriptHandover.cutNotice + "\n\nghij"))
    }
}
