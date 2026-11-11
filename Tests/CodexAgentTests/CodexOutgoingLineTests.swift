import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexOutgoingLineTests {
    func text(_ bytes: [UInt8]) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    @Test func aRequestCarriesItsIdentifierAsAWholeNumber() throws {
        let line = try CodexOutgoingLine.request(.number(3), method: "turn/interrupt", parameters: .object(["threadId": .string("t")]))
        #expect(text(line) == #"{"id":3,"method":"turn/interrupt","params":{"threadId":"t"}}"# + "\n")
    }

    @Test func aNotificationHasNoIdentifier() throws {
        #expect(text(try CodexOutgoingLine.notification(method: "initialized", parameters: .object([:]))) == #"{"method":"initialized","params":{}}"# + "\n")
    }

    @Test func anAnswerGivesBackTheIdentifierAsItCame() throws {
        let accept = try CodexOutgoingLine.response(to: .number(0), result: .object(["decision": .string("accept")]))
        #expect(text(accept) == #"{"id":0,"result":{"decision":"accept"}}"# + "\n")
        let refusal = try CodexOutgoingLine.failure(to: .text("r-1"), code: -32601, message: "not served")
        #expect(text(refusal) == #"{"error":{"code":-32601,"message":"not served"},"id":"r-1"}"# + "\n")
    }

    @Test func aLineEndInsideTextStaysInsideTheLine() throws {
        let line = try CodexOutgoingLine.notification(method: "m", parameters: .string("a\nb\r\nc"))
        #expect(line.filter { $0 == UInt8(ascii: "\n") }.count == 1)
        #expect(line.last == UInt8(ascii: "\n"))
    }
}
