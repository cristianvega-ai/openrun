import Testing
@testable import CodexAgent

@Suite struct CodexIdentifierTokenTests {
    func token(_ line: String) -> String? {
        CodexIdentifierToken.find(in: Array(line.utf8))
    }

    @Test func theTextOfTheMemberIdComesAsItIs() {
        #expect(token(#"{"id":9007199254740993,"result":{}}"#) == "9007199254740993")
        #expect(token(#"{"method":"m","id":-3}"#) == "-3")
        #expect(token(#"{"params":{"id":[1],"text":"\"id\":5"},"id" : "a-1"}"#) == #""a-1""#)
    }

    @Test func aLineWithoutAnIdentifierGivesNone() {
        #expect(token(#"{"method":"m","params":{"id":1}}"#) == nil)
        #expect(token(#"{"id":{"a":1}}"#) == nil)
        #expect(token(#"{"id""#) == nil)
    }
}
