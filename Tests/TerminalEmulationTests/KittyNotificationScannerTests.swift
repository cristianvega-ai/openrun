import Testing
@testable import TerminalEmulation

@Suite struct KittyNotificationScannerTests {
    private static func notifications(in pieces: [String]) -> [String?] {
        var scanner = KittyNotificationScanner()
        return pieces.map { scanner.notification(in: Array($0.utf8)[...]) }
    }

    @Test func findsATitleWithEitherTerminator() {
        #expect(Self.notifications(in: ["text\u{1B}]99;;Build done\u{1B}\\more"]) == ["Build done"])
        #expect(Self.notifications(in: ["\u{1B}]99;i=1;Tests passed\u{07}"]) == ["Tests passed"])
    }

    @Test func findsANotificationAcrossPieces() {
        #expect(Self.notifications(in: ["\u{1B}", "]9", "9;;Hel", "lo\u{1B}", "\\"]) == [nil, nil, nil, nil, "Hello"])
    }

    /// A notification in pieces shows at its last piece, with the body when
    /// it has one.
    @Test func joinsANotificationInPieces() {
        #expect(Self.notifications(in: ["\u{1B}]99;i=7:d=0;Waiting\u{1B}\\", "\u{1B}]99;i=7:p=body;Approve the edit\u{1B}\\"]) == [nil, "Approve the edit"])
        #expect(Self.notifications(in: ["\u{1B}]99;i=7:d=0;Waiting\u{1B}\\\u{1B}]99;i=7:p=body;\u{1B}\\"]) == ["Waiting"])
    }

    @Test func decodesBase64() {
        // "Done ✓" in base64.
        #expect(Self.notifications(in: ["\u{1B}]99;e=1;RG9uZSDinJM=\u{1B}\\"]) == ["Done ✓"])
    }

    /// Only a title or a body shows. A close, a sign of life, an icon,
    /// buttons and a query do not, and neither do other commands.
    @Test(arguments: ["p=close", "p=alive", "p=icon", "p=buttons", "p=?"])
    func aPayloadWithoutTextIsNoNotification(_ metadata: String) {
        #expect(Self.notifications(in: ["\u{1B}]99;i=1:\(metadata);x\u{1B}\\"]) == [nil])
    }

    @Test(arguments: ["\u{1B}]9;text\u{07}", "\u{1B}]999;;text\u{07}", "\u{1B}]2;99;;text\u{07}", "99;;text\u{07}", "\u{1B}]99;;cut\u{18}\u{07}", "\u{1B}]99;;cut\u{1B}[0m\u{07}"])
    func otherBytesAreNoNotification(_ output: String) {
        #expect(Self.notifications(in: [output]) == [nil])
    }

    @Test func keepsAtMostTheLimitOfACommand() {
        let long = String(repeating: "x", count: 100_000)
        let found = Self.notifications(in: ["\u{1B}]99;;" + long + "\u{1B}\\"])
        #expect(found.first??.utf8.count == KittyNotificationScanner.commandByteLimit - 4)
    }
}
