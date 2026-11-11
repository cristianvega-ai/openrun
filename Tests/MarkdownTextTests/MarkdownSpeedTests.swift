import Foundation
import Testing
@testable import MarkdownText

/// A message of a megabyte must not stall the main thread.
struct MarkdownSpeedTests {
    static let megabyte: String = {
        var text = ""
        while text.utf8.count < 1024 * 1024 { text += MarkdownSamples.messages[0] + "\n\n" }
        return text
    }()

    @Test func aMegabyteParsesInPartsOfASecond() {
        let clock = ContinuousClock()
        var document = MarkdownDocument()
        let elapsed = clock.measure { document.update(text: Self.megabyte, isComplete: true) }
        print("A parse of \(Self.megabyte.utf8.count) bytes took \(elapsed).")
        #expect(document.blocks.count > 10_000)
        #expect(elapsed < .seconds(2))
    }

    @Test func anUpdateAtTheEndOfAMegabyteIsCheap() {
        var document = MarkdownDocument(text: Self.megabyte, isComplete: false)
        var text = Self.megabyte
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for index in 0..<60 {
                text += "word \(index) **bold** "
                document.update(text: text, isComplete: false)
            }
        }
        print("60 updates at the end of a megabyte took \(elapsed / 60) each.")
        #expect(elapsed / 60 < .milliseconds(8))
    }

    @Test func spansOfAParagraphOfFourKilobytesAreCheap() {
        let paragraph = String(repeating: "Some **bold** and `code` with a [link](https://example.com). ", count: 64)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = MarkdownInlineParser.spans(of: paragraph, isStreaming: true) }
        print("The spans of \(paragraph.utf8.count) bytes took \(elapsed).")
        #expect(elapsed < .milliseconds(20))
    }
}
