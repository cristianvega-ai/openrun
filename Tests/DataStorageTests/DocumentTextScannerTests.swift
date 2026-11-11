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
}
