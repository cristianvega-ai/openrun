import Foundation
import Testing
import AgentConversation

@Suite struct JSONValueTests {
    @Test func aToolInputDecodesWithEachKindOfValue() throws {
        let text = #"{"command":"touch a.txt","timeout":120,"background":false,"tags":["a",null],"extra":{"depth":1.5}}"#
        let value = try JSONValue(decoding: Data(text.utf8))
        #expect(value["command"]?.string == "touch a.txt")
        #expect(value["timeout"]?.integer == 120)
        #expect(value["background"]?.bool == false)
        #expect(value["tags"]?.array == [.string("a"), .null])
        #expect(value["extra"]?["depth"]?.number == 1.5)
        #expect(value["missing"] == nil)
    }

    @Test func aValueSurvivesAnEncodeAndADecode() throws {
        let value = JSONValue.object(["list": .array([.bool(true), .number(-2), .string("é\n")]), "none": .null])
        let data = try JSONEncoder().encode(value)
        #expect(try JSONValue(decoding: data) == value)
    }

    @Test func aNumberWithAFractionIsNoInteger() {
        #expect(JSONValue.number(1.5).integer == nil)
        #expect(JSONValue.number(1e300).integer == nil)
        #expect(JSONValue.string("1").integer == nil)
    }

    @Test func aNestingThatIsTooDeepIsRefusedAndDoesNotTrap() {
        let text = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)
        #expect(throws: (any Error).self) { try JSONValue(decoding: Data(text.utf8)) }
    }

    @Test func textThatIsNotJSONIsRefused() {
        for text in ["", "{", "not json", "{\"a\":}", "\u{FEFF}"] {
            #expect(throws: (any Error).self) { try JSONValue(decoding: Data(text.utf8)) }
        }
    }
}
