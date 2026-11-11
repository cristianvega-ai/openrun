import MarkdownText
import Testing

@testable import ChatView

@MainActor struct TranscriptRowContextTests {
    let context = TranscriptRowContext(palette: ChatPalette(appearance: .graphite))

    @Test func theTextOfBlocksIsTheirRenderedText() {
        context.documents["text:a"] = MarkdownDocument(text: "# Title\n\nOne **bold** word.\n\n- An item", isComplete: true)
        #expect(context.text(ofBlocks: 0..<3, in: "text:a").string == "Title\nOne bold word.\n•\tAn item")
        #expect(context.text(ofBlocks: 1..<2, in: "text:a").string == "One bold word.")
    }

    @Test func aChangedBlockShowsItsNewText() {
        context.documents["text:a"] = MarkdownDocument(text: "First.\n\nSecond", isComplete: false)
        _ = context.text(ofBlocks: 0..<2, in: "text:a")
        context.documents["text:a"]?.update(text: "First.\n\nSecond and third.", isComplete: true)
        #expect(context.text(ofBlocks: 0..<2, in: "text:a").string == "First.\nSecond and third.")
    }

    @Test func aMessageThatWentHasNoText() {
        context.documents["text:a"] = MarkdownDocument(text: "Gone soon.", isComplete: true)
        _ = context.text(ofBlocks: 0..<1, in: "text:a")
        context.documents = [:]
        #expect(context.text(ofBlocks: 0..<1, in: "text:a").length == 0)
    }
}
