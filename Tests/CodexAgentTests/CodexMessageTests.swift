import AgentConversation
import Foundation
import Testing
@testable import CodexAgent

@Suite struct CodexMessageTests {
    func message(_ text: String) throws -> CodexMessage? {
        CodexMessage(try JSONValue(decoding: Data(text.utf8)))
    }

    @Test func eachFormOfTheProtocolIsRead() throws {
        #expect(try message(#"{"id":0,"result":{"codexHome":"/config/codex"}}"#)
            == .response(.number(0), result: .object(["codexHome": .string("/config/codex")])))
        #expect(try message(#"{"error":{"code":-32600,"message":"no rollout found"},"id":2}"#)
            == .failure(.number(2), code: -32600, message: "no rollout found"))
        #expect(try message(#"{"method":"turn/started","params":{"threadId":"t"},"emittedAtMs":1}"#)
            == .notification(method: "turn/started", parameters: .object(["threadId": .string("t")])))
        #expect(try message(#"{"method":"item/fileChange/requestApproval","id":2,"params":{}}"#)
            == .request(.number(2), method: "item/fileChange/requestApproval", parameters: .object([:])))
    }

    @Test func aRefusalOfAnUnreadableRequestHasNoIdentifier() throws {
        #expect(try message(#"{"id":null,"error":{"code":-32700,"message":"parse error"}}"#)
            == .failure(nil, code: -32700, message: "parse error"))
    }

    @Test func otherValuesAreNoMessage() throws {
        for text in ["[1]", "\"text\"", "{}", #"{"id":1}"#, #"{"id":1.5,"result":{}}"#, #"{"result":{}}"#, #"{"method":5}"#,
                     #"{"method":"x","id":[1]}"#, #"{"id":1,"error":"text"}"#] {
            #expect(try message(text) == nil, "\(text)")
        }
    }
}
