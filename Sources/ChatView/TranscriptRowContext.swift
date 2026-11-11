import AgentConversation
import AppKit
import MarkdownText

/// What the rows of a transcript share: the transcript, the colors, the
/// parsed messages, and the parts that the user opened.
@MainActor final class TranscriptRowContext {
    private struct RenderedBlock {
        var block: MarkdownBlock
        var previous: MarkdownBlock?
        var isStreaming: Bool
        var text: NSAttributedString
    }

    var transcript = Transcript()
    var palette: ChatPalette {
        didSet {
            renderer = MarkdownRenderer(style: palette.markdownStyle)
            renderedBlocks = [:]
        }
    }
    private(set) var renderer: MarkdownRenderer
    /// The parsed text of each agent message.
    var documents: [String: MarkdownDocument] = [:] {
        didSet {
            if renderedBlocks.count > documents.count { renderedBlocks = renderedBlocks.filter { documents[$0.key] != nil } }
        }
    }
    var agentName = "The agent"
    /// The parts of rows that the user opened, such as a tool call.
    var openedParts: Set<String> = []
    weak var actions: TranscriptRowActions?
    /// The permission requests that the user answered. Their buttons stay
    /// off until the answer comes back in the transcript.
    var answeredRequests: Set<String> = []
    var hasEarlierHistory = false
    var isLoadingEarlierHistory = false
    /// The height of the transcript on the screen, which a request that
    /// waits fits in.
    var viewportHeight: CGFloat = 0
    /// The permission requests that VoiceOver announced.
    var announcedRequests: Set<String> = []
    /// The rendered blocks of each message by their index.
    private var renderedBlocks: [String: [Int: RenderedBlock]] = [:]

    init(palette: ChatPalette) {
        self.palette = palette
        renderer = MarkdownRenderer(style: palette.markdownStyle)
    }

    func item(_ identifier: String) -> TranscriptItemContent? {
        transcript.item(withIdentifier: identifier)?.content
    }

    /// The text of a run of blocks of a message. Each block renders again
    /// only when it or the block before it changed.
    func text(ofBlocks range: Range<Int>, in item: String) -> NSAttributedString {
        guard let document = documents[item] else { return NSAttributedString() }
        let blocks = document.blocks
        let result = NSMutableAttributedString()
        for index in range where index < blocks.count {
            let previous = index > range.lowerBound ? blocks[index - 1] : nil
            let isStreaming = !document.isComplete && index == blocks.count - 1
            var rendered = renderedBlocks[item]?[index]
            if rendered == nil || rendered?.block != blocks[index] || rendered?.previous != previous || rendered?.isStreaming != isStreaming {
                let text = renderer.attributedString(for: blocks[index], after: previous, isStreaming: isStreaming)
                rendered = RenderedBlock(block: blocks[index], previous: previous, isStreaming: isStreaming, text: text)
                renderedBlocks[item, default: [:]][index] = rendered
            }
            if result.length > 0 { result.append(MarkdownRenderer.separator(after: result)) }
            if let rendered { result.append(rendered.text) }
        }
        return result
    }
}
