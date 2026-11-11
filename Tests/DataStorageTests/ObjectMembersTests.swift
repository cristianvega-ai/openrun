@testable import DataStorage
import Foundation
import Testing

@Suite struct ObjectMembersTests {
    static func text(_ data: Data?) -> String? {
        data.map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func eachValueKeepsItsExactText() throws {
        let source = #"""
            { "large" : 123456789012345678901234567890, "unsigned":18446744073709551615,
              "zero": -0.0, "exponent": 1E+400, "text": "a \"}] b\\", "flag": true,
              "nested": {"list": [1, {"x": "]"}], "empty": {}}, "none": null, "aé": []}
            """#
        let members = try #require(ObjectMembers(parsing: Data(source.utf8)))
        #expect(members.values.count == 9)
        #expect(Self.text(members["large"]) == "123456789012345678901234567890")
        #expect(Self.text(members["unsigned"]) == "18446744073709551615")
        #expect(Self.text(members["zero"]) == "-0.0")
        #expect(Self.text(members["exponent"]) == "1E+400")
        #expect(Self.text(members["text"]) == #""a \"}] b\\""#)
        #expect(Self.text(members["flag"]) == "true")
        #expect(Self.text(members["nested"]) == #"{"list": [1, {"x": "]"}], "empty": {}}"#)
        #expect(Self.text(members["none"]) == "null")
        #expect(Self.text(members["aé"]) == "[]")
    }

    @Test func textThatIsNotOneObjectHasNoMembers() {
        for bad in ["", "[]", "{", #"{"a" 1}"#, #"{"a": 1,}"#, #"{"a": 1} {}"#, #"{"a": "open}"#] {
            #expect(ObjectMembers(parsing: Data(bad.utf8)) == nil)
        }
        #expect(ObjectMembers(parsing: Data(" { } ".utf8))?.values.isEmpty == true)
    }

    /// The members render as the encoder writes them, so a file that
    /// holds no unknown member stays the same byte for byte.
    @Test func theRenderedTextIsTheTextOfTheEncoder() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let document = ["b/c": ["x": [1, 2]], "a": ["y": []]]
        var encoded = try encoder.encode(document)
        encoded.append(UInt8(ascii: "\n"))
        let members = try #require(ObjectMembers(parsing: encoded))
        #expect(Self.text(members.rendered()) == Self.text(encoded))
    }
}
