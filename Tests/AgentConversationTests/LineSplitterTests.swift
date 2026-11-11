import Testing
import AgentConversation

@Suite struct LineSplitterTests {
    @Test func linesComeWholeAtEverySplitOfTheBytes() {
        let output = Array("{\"a\":1}\n\n{\"b\":\"é\"}\n{\"c\"".utf8)
        for split in 0...output.count {
            var splitter = LineSplitter(lineByteLimit: 100)
            let pieces = splitter.append(output[..<split]) + splitter.append(output[split...])
            #expect(pieces == [.line(Array("{\"a\":1}".utf8)), .line([]), .line(Array("{\"b\":\"é\"}".utf8))], "split \(split)")
            #expect(splitter.finish() == .cutShort(start: Array("{\"c\"".utf8), byteCount: 4))
            #expect(splitter.finish() == nil)
        }
    }

    @Test func aLineOverTheLimitKeepsOnlyItsStartAndTheNextLineIsRead() {
        var splitter = LineSplitter(lineByteLimit: SourceLine.byteLimit * 2)
        var pieces: [LineSplitter.Piece] = []
        let chunk = [UInt8](repeating: UInt8(ascii: "x"), count: 10_000)
        for _ in 0..<1_000 { pieces += splitter.append(chunk) }
        pieces += splitter.append(Array("\n{}\n".utf8))
        #expect(pieces.count == 2)
        let start = [UInt8](repeating: UInt8(ascii: "x"), count: SourceLine.byteLimit)
        #expect(pieces.first == .tooLong(start: start, byteCount: 10_000_000))
        #expect(pieces.last == .line(Array("{}".utf8)))
    }
}
