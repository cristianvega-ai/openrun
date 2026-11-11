@testable import DataStorage
import Testing

@Suite struct DocumentTextScannerTests {
    @Test(arguments: [
        (#" 18446744073709551615 ,"#, "18446744073709551615"),
        ("-0.0}", "-0.0"),
        (#""a \"}] b\\" "#, #""a \"}] b\\""#),
        (#"{"list": [1, {"x": "]"}]}, 2"#, #"{"list": [1, {"x": "]"}]}"#),
        ("null]", "null"),
    ])
    func aValueEndsWhereItsTextEnds(text: String, expected: String) throws {
        var scanner = DocumentTextScanner(bytes: Array(text.utf8))
        let found = scanner.value()
        let value = try #require(found)
        #expect(String(decoding: value, as: UTF8.self) == expected)
    }

    @Test func anOpenValueHasNoEnd() {
        for text in [#""open"#, #"{"a": [1"#, ""] {
            var scanner = DocumentTextScanner(bytes: Array(text.utf8))
            let found = scanner.value()
            #expect(found == nil)
        }
    }

    static func isValid(_ text: String) -> Bool {
        var scanner = DocumentTextScanner(bytes: Array(text.utf8))
        let found = scanner.value()
        return found != nil && scanner.atEnd
    }

    @Test func strictJSONPasses() {
        #expect(Self.isValid(#"[-0.0, 1E+400, 0.5e-3, -12, "\u00e9\n\/\"", {}, [], true, false, null, {"a": [{}]}]"#))
    }

    /// Foundation's decoder takes some of these. A kept value goes back
    /// into the file, so each one must fail here.
    @Test(arguments: [
        "\"a\tb\"", "\"a\nb\"", #""\q""#, #""\u12""#, #""\u12G4""#, "\"open",
        "01", "tru", "nul", "1.", "-", "1e", "1e+", ".5", "+1", "NaN", "Infinity", "0x1",
        "[01]", "[1,]", "{\"a\": 1,}", "[1 2]", "{\"a\" 1}", "{1: 2}", "[,]", "[", "{\"a\": [1}",
    ])
    func textThatIsNotStrictJSONFails(text: String) {
        #expect(!Self.isValid(text))
    }

    @Test func textDeeperThanTheLimitFails() {
        let depth = DocumentTextScanner.depthLimit
        #expect(Self.isValid(String(repeating: "[", count: depth) + String(repeating: "]", count: depth)))
        #expect(!Self.isValid(String(repeating: "[", count: depth + 1) + String(repeating: "]", count: depth + 1)))
    }
}
