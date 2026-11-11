import Foundation
@testable import Settings
import Testing

@Suite struct StoredValueTests {
    static func decode(_ text: String) throws -> StoredValue {
        try JSONDecoder().decode(StoredValue.self, from: Data(text.utf8))
    }

    @Test func eachJSONValueKeepsItsType() throws {
        #expect(try Self.decode("null") == .null)
        #expect(try Self.decode("true") == .flag(true))
        #expect(try Self.decode("13") == .integer(13))
        #expect(try Self.decode("9007199254740993") == .integer(9_007_199_254_740_993))
        #expect(try Self.decode("13.5") == .number(13.5))
        #expect(try Self.decode(#""13""#) == .string("13"))
        #expect(try Self.decode(#"[1, "a", false]"#) == .array([.integer(1), .string("a"), .flag(false)]))
        #expect(try Self.decode(#"{"a": {"b": []}}"#) == .object(["a": .object(["b": .array([])])]))
    }

    @Test func aValueRoundTrips() throws {
        let text = #"{"list":[1,2.5,"x",null,true],"nested":{"deep":{"value":-7}}}"#
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let value = try Self.decode(text)
        #expect(String(decoding: try encoder.encode(value), as: UTF8.self) == text)
    }
}
