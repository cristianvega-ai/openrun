import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexRequestIdentifierTests {
    @Test func aWholeNumberOrTextIsAnIdentifier() {
        #expect(CodexRequestIdentifier(.number(7)) == .number(7))
        #expect(CodexRequestIdentifier(.string("a-1")) == .text("a-1"))
        #expect(CodexRequestIdentifier(.number(7))?.token == "7")
        #expect(CodexRequestIdentifier(.string("a-1"))?.token == #""a-1""#)
    }

    @Test func otherValuesAreNoIdentifier() {
        for value: JSONValue in [.null, .bool(true), .number(1.5), .number(1e300), .array([]), .object([:])] {
            #expect(CodexRequestIdentifier(value) == nil)
        }
    }

    @Test func theDescriptionIsTheNumberOrTheText() {
        #expect(CodexRequestIdentifier.number(12).description == "12")
        #expect(CodexRequestIdentifier.text("x").description == "x")
    }

    /// The identifier of a request of the server, read from its line.
    func identifier(_ token: String) throws -> CodexRequestIdentifier? {
        var reader = CodexMessageReader()
        let line = #"{"params":{"id":[1]},"id":"# + token + #","method":"item/commandExecution/requestApproval"}"# + "\n"
        guard case .message(.request(let identifier, _, _), _)? = reader.read(Array(line.utf8)).first else { return nil }
        return identifier
    }

    @Test func anAnswerCarriesTheIdentifierExactlyAsItCame() throws {
        for token in ["9007199254740993", "9999999999999999999", "-3", #""a\u002d1""#, #""x""#] {
            let request = try #require(try identifier(token))
            let answer = String(decoding: try CodexOutgoingLine.response(to: request, result: .object([:])), as: UTF8.self)
            #expect(answer == #"{"id":"# + token + #","result":{}}"# + "\n")
        }
        #expect(try identifier("1.5") == nil)
        #expect(try identifier(#""a\u002d1""#)?.description == "a-1")
    }
}
