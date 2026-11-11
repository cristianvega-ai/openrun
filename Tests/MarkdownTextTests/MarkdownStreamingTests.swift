import Testing
@testable import MarkdownText

/// Text that is cut at every position, as it streams.
struct MarkdownStreamingTests {
    /// A block before the last never changes as text comes, and the last
    /// block shows as the kind of block that it becomes.
    @Test(arguments: MarkdownSamples.messages) func eachCutShowsTheFinalBlocks(sample: String) {
        let final = MarkdownDocument(text: sample).blocks
        for cut in sample.indices {
            let blocks = MarkdownDocument(text: String(sample[..<cut]), isComplete: false).blocks
            for (index, block) in blocks.enumerated() {
                #expect(index < final.count, "cut at \(sample.distance(from: sample.startIndex, to: cut))")
                guard index < final.count else { break }
                if index < blocks.count - 1 {
                    #expect(block == final[index], "cut at \(sample.distance(from: sample.startIndex, to: cut))")
                } else {
                    #expect(Self.form(block) == Self.form(final[index]), "cut at \(sample.distance(from: sample.startIndex, to: cut))")
                }
            }
        }
    }

    /// A document that grows piece by piece ends with the same blocks as
    /// one parse of each text.
    @Test(arguments: MarkdownSamples.messages) func growingTextGivesTheSameBlocksAsAFreshParse(sample: String) {
        var document = MarkdownDocument(text: "", isComplete: false)
        var cut = sample.startIndex
        var step = 1
        while cut < sample.endIndex {
            cut = sample.index(cut, offsetBy: step, limitedBy: sample.endIndex) ?? sample.endIndex
            step = step % 7 + 1
            let before = document.blocks
            let firstChange = document.update(text: String(sample[..<cut]), isComplete: false)
            let fresh = MarkdownDocument(text: String(sample[..<cut]), isComplete: false).blocks
            #expect(document.blocks == fresh)
            #expect(Array(before.prefix(firstChange)) == Array(fresh.prefix(firstChange)))
        }
        document.update(text: sample, isComplete: true)
        #expect(document.blocks == MarkdownDocument(text: sample).blocks)
    }

    /// The kind of a block without its content.
    static func form(_ block: MarkdownBlock) -> String {
        switch block.kind {
        case .paragraph: "paragraph"
        case .heading(let level, _): "heading \(level)"
        case .listItem(let marker, _): "item \(marker)"
        case .code: "code"
        case .table: "table"
        case .rule: "rule"
        }
    }
}
