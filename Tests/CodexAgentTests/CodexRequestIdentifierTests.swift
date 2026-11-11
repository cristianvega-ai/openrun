import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexRequestIdentifierTests {
    @Test func aWholeNumberOrTextIsAnIdentifier() {
        #expect(CodexRequestIdentifier(.number(7)) == .number(7))
        #expect(CodexRequestIdentifier(.string("a-1")) == .text("a-1"))
        #expect(CodexRequestIdentifier(.number(7)).map(\.jsonValue) == .number(7))
        #expect(CodexRequestIdentifier(.string("a-1")).map(\.jsonValue) == .string("a-1"))
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
}
