import Testing

@testable import CommandLineTool

@Suite struct DetachKeyRecognizerTests {
    private let start = ContinuousClock.now

    private func scan(_ text: String) -> DetachKeyRecognizer.Scan {
        var recognizer = DetachKeyRecognizer()
        return recognizer.scan(Array(text.utf8), at: start)
    }

    private func detaches(_ text: String) -> Bool {
        scan(text).foundDetachKey
    }

    @Test func theByteFromAPlainKeyboardDetaches() {
        #expect(scan("\u{1D}") == .init(bytesToSend: [], foundDetachKey: true))
    }

    @Test(arguments: [
        "\u{1B}[93;5u",
        "\u{1B}[93;5:1u",
        "\u{1B}[93;5:2u",
        "\u{1B}[93:93;5u",
        "\u{1B}[93:93:93;5:1u",
        "\u{1B}[93;5;93u",
        "\u{1B}[93;5:1;93u",
        "\u{1B}[93;69u",
        "\u{1B}[93;133u",
        "\u{1B}[93;197u",
    ])
    func theKittyFormDetaches(sequence: String) {
        #expect(detaches(sequence))
    }

    @Test func theModifyOtherKeysFormDetaches() {
        #expect(detaches("\u{1B}[27;5;93~"))
    }

    @Test func aReleaseDoesNotDetach() {
        #expect(!detaches("\u{1B}[93;5:3u"))
    }
}
