import AgentConversation
import Foundation
import Testing
@testable import CodexAgent

@Suite struct CodexTurnTests {
    @Test func aTurnSendsItsTextImagesAndChanges() {
        let image = MessageImage(mediaType: "image/png", data: Data([1, 2, 3]))
        let turn = CodexTurn(messageIdentifier: "message-1", text: "hi", images: [image], reasoningEffort: "high", sandbox: .readOnly)
        #expect(turn.parameters(thread: "t") == .object([
            "threadId": .string("t"), "clientUserMessageId": .string("message-1"), "effort": .string("high"),
            "sandboxPolicy": .object(["type": .string("readOnly")]),
            "input": .array([
                .object(["type": .string("text"), "text": .string("hi")]),
                .object(["type": .string("image"), "url": .string("data:image/png;base64,AQID")]),
            ]),
        ]))
    }
}
