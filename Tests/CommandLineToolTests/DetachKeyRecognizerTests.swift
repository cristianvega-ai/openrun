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

    @Test(arguments: [
        "\u{1B}[93u",
        "\u{1B}[93;1u",
        "\u{1B}[93;2u",
        "\u{1B}[93;3u",
        "\u{1B}[93;4u",
        "\u{1B}[93;6u",
        "\u{1B}[93;7u",
        "\u{1B}[93;9u",
        "\u{1B}[93;13u",
        "\u{1B}[93;17u",
        "\u{1B}[93;33u",
        "\u{1B}[93;37u",
        "\u{1B}[27;3;93~",
        "\u{1B}[27;6;93~",
        "\u{1B}[27;1;93~",
    ])
    func otherModifiersDoNotDetach(sequence: String) {
        #expect(!detaches(sequence))
        #expect(scan(sequence).bytesToSend == Array(sequence.utf8))
    }

    @Test(arguments: [
        "\u{1B}[91;5u",
        "\u{1B}[92;5u",
        "\u{1B}[9;5u",
        "\u{1B}[930;5u",
        "\u{1B}[27;5;91~",
        "\u{1B}[27;5;9~",
        "\u{1B}[28;5;93~",
        "\u{1B}[93;5A",
    ])
    func otherKeysDoNotDetach(sequence: String) {
        #expect(!detaches(sequence))
        #expect(scan(sequence).bytesToSend == Array(sequence.utf8))
    }

    @Test func plainTextPassesThroughUnchanged() {
        #expect(scan("echo hello\r") == .init(bytesToSend: Array("echo hello\r".utf8), foundDetachKey: false))
    }

    @Test func aLoneEscapeKeyIsHeldForTheHoldTimeAndThenSent() {
        var recognizer = DetachKeyRecognizer()
        #expect(recognizer.scan([0x1B], at: start) == .init(bytesToSend: [], foundDetachKey: false))
        #expect(recognizer.remainingHold(at: start) == .milliseconds(20))
        #expect(recognizer.remainingHold(at: start + .milliseconds(15)) == .milliseconds(5))
        #expect(recognizer.releaseExpired(at: start + .milliseconds(19)).isEmpty)
        #expect(recognizer.releaseExpired(at: start + .milliseconds(20)) == [0x1B])
        #expect(recognizer.remainingHold(at: start + .milliseconds(20)) == nil)
        #expect(recognizer.releaseExpired(at: start + .milliseconds(40)).isEmpty)
    }

    @Test func nothingIsHeldWhenNothingIsIncomplete() {
        var recognizer = DetachKeyRecognizer()
        _ = recognizer.scan(Array("abc".utf8), at: start)
        #expect(recognizer.remainingHold(at: start) == nil)
    }

    @Test func anIncompleteStartOfAFormIsHeldAfterOtherBytesAreSent() {
        var recognizer = DetachKeyRecognizer()
        #expect(recognizer.scan(Array("ab\u{1B}[".utf8), at: start) == .init(bytesToSend: Array("ab".utf8), foundDetachKey: false))
        #expect(recognizer.releaseExpired(at: start + .milliseconds(20)) == Array("\u{1B}[".utf8))
    }

    @Test(arguments: [
        "\u{1B}x",
        "\u{1B}[1",
        "\u{1B}[930",
        "\u{1B}[91;",
        "\u{1B}[27;3",
        "\u{1B}[27;5;91",
        "\u{1B}[28",
        "\u{1B}[93;5 ",
        "\u{1B}[?",
        "\u{1B}[<",
        "\u{1B}[93;5;93;1",
        "\u{1B}[27;5;93;",
        "\u{1B}]0;",
    ])
    func bytesThatCannotStartADetachFormAreNeverHeld(text: String) {
        var recognizer = DetachKeyRecognizer()
        let scan = recognizer.scan(Array(text.utf8), at: start)
        #expect(scan == .init(bytesToSend: Array(text.utf8), foundDetachKey: false))
        #expect(recognizer.remainingHold(at: start) == nil)
    }

    @Test(arguments: [
        "\u{1B}[9",
        "\u{1B}[93",
        "\u{1B}[93:",
        "\u{1B}[93:93;",
        "\u{1B}[93;",
        "\u{1B}[93;5",
        "\u{1B}[93;5:1;",
        "\u{1B}[2",
        "\u{1B}[27;",
        "\u{1B}[27;5;",
        "\u{1B}[27;5;9",
    ])
    func everyStartOfADetachFormIsHeld(text: String) {
        var recognizer = DetachKeyRecognizer()
        #expect(recognizer.scan(Array(text.utf8), at: start).bytesToSend.isEmpty)
        #expect(recognizer.remainingHold(at: start) == .milliseconds(20))
    }

    @Test(arguments: ["\u{1D}", "\u{1B}[93;5u", "\u{1B}[27;5;93~"])
    func onlyTheBytesBeforeTheKeyAreSent(key: String) {
        #expect(scan("ls\r" + key + "ignored") == .init(bytesToSend: Array("ls\r".utf8), foundDetachKey: true))
    }

    @Test func otherSequencesBeforeTheKeyAreSentUnchanged() {
        #expect(scan("\u{1B}[A\u{1B}[93;5u") == .init(bytesToSend: Array("\u{1B}[A".utf8), foundDetachKey: true))
    }

    @Test(arguments: [
        "\u{1B}[93;5u",
        "\u{1B}[93;5:1u",
        "\u{1B}[93:93;5:2;93u",
        "\u{1B}[27;5;93~",
    ])
    func aFormSplitAtEveryPositionDetaches(sequence: String) {
        let bytes = Array(sequence.utf8)
        for splitIndex in 1..<bytes.count {
            var recognizer = DetachKeyRecognizer()
            let first = recognizer.scan(Array("x".utf8) + bytes[..<splitIndex], at: start)
            #expect(first == .init(bytesToSend: Array("x".utf8), foundDetachKey: false), "split at \(splitIndex)")
            let second = recognizer.scan(Array(bytes[splitIndex...]), at: start + .milliseconds(5))
            #expect(second == .init(bytesToSend: [], foundDetachKey: true), "split at \(splitIndex)")
            #expect(recognizer.remainingHold(at: start + .milliseconds(5)) == nil, "split at \(splitIndex)")
        }
    }

    @Test func aFormSplitIntoSingleBytesDetaches() {
        var recognizer = DetachKeyRecognizer()
        var instant = start
        var results: [DetachKeyRecognizer.Scan] = []
        for byte in Array("\u{1B}[93;5u".utf8) {
            results.append(recognizer.scan([byte], at: instant))
            instant = instant + .milliseconds(3)
        }
        #expect(results.dropLast().allSatisfy { $0 == .init(bytesToSend: [], foundDetachKey: false) })
        #expect(results.last == .init(bytesToSend: [], foundDetachKey: true))
    }

    @Test func theHoldDoesNotStartAgainWhenMoreOfTheSameFormArrives() {
        var recognizer = DetachKeyRecognizer()
        _ = recognizer.scan(Array("\u{1B}[9".utf8), at: start)
        _ = recognizer.scan(Array("3;".utf8), at: start + .milliseconds(15))
        #expect(recognizer.remainingHold(at: start + .milliseconds(15)) == .milliseconds(5))
        #expect(recognizer.releaseExpired(at: start + .milliseconds(20)) == Array("\u{1B}[93;".utf8))
    }
}
