import Testing
@testable import MarkdownText

struct MarkdownDocumentTests {
    @Test func aLastLineOfMarksWaitsForMoreText() {
        #expect(MarkdownDocument(text: "Text\n#", isComplete: false).blocks.count == 1)
        #expect(MarkdownDocument(text: "Text\n```sw", isComplete: false).blocks.count == 1)
        #expect(MarkdownDocument(text: "Text\n> - [", isComplete: false).blocks.count == 1)
        #expect(MarkdownDocument(text: "Text\n- [x] d", isComplete: false).blocks.count == 2)
        #expect(MarkdownDocument(text: "Text\n#", isComplete: true).blocks.count == 2)
        #expect(MarkdownDocument(text: "-", isComplete: false).blocks.isEmpty)
    }

    @Test func lineEndsOfWindowsAreRead() {
        #expect(MarkdownDocument(text: "# A\r\nText\r\n").blocks.map(\.kind) == [.heading(level: 1, text: "A"), .paragraph("Text")])
    }

    @Test func anUpdateTellsTheFirstBlockThatChanged() {
        var document = MarkdownDocument(text: "# One\n\nTwo", isComplete: false)
        #expect(document.update(text: "# One\n\nTwo three", isComplete: false) == 1)
        #expect(document.update(text: "# One\n\nTwo three\n\nFour", isComplete: true) == 2)
        #expect(document.update(text: "Other\n\nTwo", isComplete: true) == 0)
        #expect(document.blocks == MarkdownDocument(text: "Other\n\nTwo").blocks)
    }
}
