import Foundation

/// The blocks of one Markdown text that can grow while it streams.
///
/// A new text that starts with the old one parses again only from the
/// start of one of the last blocks, so a long message that grows costs
/// little. While the text streams, a last line that holds only marks, such
/// as `#`, `-` or the start of a code fence, waits for more text. It would
/// otherwise show as one kind of block and then change to another.
public struct MarkdownDocument: Sendable, Hashable {
    private struct RestartPoint: Hashable, Sendable {
        /// The UTF-8 offset of the line in the text.
        var offset: Int
        var blockIndex: Int
        var continuesParagraph: Bool
    }

    public private(set) var text = ""
    public private(set) var isComplete = true
    public private(set) var blocks: [MarkdownBlock] = []
    /// The UTF-8 length of the part of `text` that the blocks show.
    private var shownByteCount = 0
    private var restartPoints: [RestartPoint] = []

    public init(text: String = "", isComplete: Bool = true) {
        update(text: text, isComplete: isComplete)
    }

    /// Takes the whole text as it is now.
    /// - Returns: The index of the first block that changed. The blocks
    ///   before it are the same as before.
    @discardableResult
    public mutating func update(text newText: String, isComplete newIsComplete: Bool) -> Int {
        let shown = Self.shownPart(of: newText, isComplete: newIsComplete)
        let shownBytes = shown.utf8
        let grows = shownBytes.count >= shownByteCount && Self.startsWith(newText, text, byteCount: shownByteCount)
        let restart = grows && restartPoints.count >= 2 ? restartPoints[restartPoints.count - 2]
            : RestartPoint(offset: 0, blockIndex: 0, continuesParagraph: false)
        let start = shownBytes.index(shownBytes.startIndex, offsetBy: restart.offset)
        let (lines, offsets) = Self.lines(of: shown[start...])
        var parser = MarkdownBlockParser(lines: lines, isComplete: newIsComplete, continuesParagraph: restart.continuesParagraph)
        parser.run()
        // The arrays change in place at their end, because a copy of the
        // blocks of a long text for each piece would cost too much.
        let oldTail = blocks[restart.blockIndex...]
        var firstChange = restart.blockIndex
        while firstChange - restart.blockIndex < min(parser.blocks.count, oldTail.count),
            parser.blocks[firstChange - restart.blockIndex] == oldTail[firstChange] {
            firstChange += 1
        }
        blocks.replaceSubrange(restart.blockIndex..., with: parser.blocks)
        let kept = restartPoints.lastIndex { $0.blockIndex < restart.blockIndex && $0.offset < restart.offset }.map { $0 + 1 } ?? 0
        restartPoints.replaceSubrange(kept..., with: parser.restartPoints.map {
            RestartPoint(offset: restart.offset + offsets[$0.lineIndex], blockIndex: restart.blockIndex + $0.blockIndex,
                continuesParagraph: $0.continuesParagraph)
        })
        text = newText
        isComplete = newIsComplete
        shownByteCount = shownBytes.count
        return firstChange
    }

    /// Whether the first `byteCount` bytes of two texts are the same.
    private static func startsWith(_ text: String, _ start: String, byteCount: Int) -> Bool {
        var text = text
        var start = start
        return text.withUTF8 { new in
            start.withUTF8 { old in
                new.count >= byteCount && old.count >= byteCount
                    && (byteCount == 0 || memcmp(new.baseAddress!, old.baseAddress!, byteCount) == 0)
            }
        }
    }

    /// The text without a last line that must wait for more text.
    static func shownPart(of text: String, isComplete: Bool) -> Substring {
        guard !isComplete, let lastLineEnd = text.utf8.lastIndex(of: UInt8(ascii: "\n")) else {
            return isComplete || !mustWait(text[...]) ? text[...] : text.prefix(0)
        }
        let last = text[text.index(after: lastLineEnd)...]
        return mustWait(last) ? text[..<lastLineEnd] : text[...]
    }

    private static func mustWait(_ line: Substring) -> Bool {
        var rest = MarkdownLine.trimmed(line)
        while let quoted = MarkdownLine.quoteContent(rest) { rest = MarkdownLine.trimmed(quoted) }
        if rest.hasPrefix("``") || rest.hasPrefix("~~~") { return true }
        return rest.count <= 12 && rest.allSatisfy { " \t#>*+-|:`~=_.)[]xX0123456789".contains($0) }
    }

    /// The lines of `text` without their line ends, and the UTF-8 offset
    /// of each line from the start of `text`.
    private static func lines(of text: Substring) -> ([Substring], [Int]) {
        var lines: [Substring] = []
        var offsets: [Int] = []
        let utf8 = text.utf8
        var lineStart = utf8.startIndex
        var offset = 0
        var position = utf8.startIndex
        while position < utf8.endIndex {
            if utf8[position] == UInt8(ascii: "\n") {
                lines.append(line(text, from: lineStart, to: position))
                offsets.append(offset)
                let next = utf8.index(after: position)
                offset += utf8.distance(from: lineStart, to: next)
                lineStart = next
            }
            position = utf8.index(after: position)
        }
        lines.append(line(text, from: lineStart, to: utf8.endIndex))
        offsets.append(offset)
        return (lines, offsets)
    }

    private static func line(_ text: Substring, from start: String.Index, to end: String.Index) -> Substring {
        let line = text[start..<end]
        return line.utf8.last == UInt8(ascii: "\r") ? text[start..<text.utf8.index(before: end)] : line
    }
}
