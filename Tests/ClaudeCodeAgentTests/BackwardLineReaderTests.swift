import Foundation
import Testing
@testable import ClaudeCodeAgent

@Suite struct BackwardLineReaderTests {
    func lines(of text: [UInt8], lineByteLimit: Int) throws -> [BackwardLineReader.Line] {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "backward-lines-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(text).write(to: url)
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let reader = BackwardLineReader(file: file, end: UInt64(text.count), lineByteLimit: lineByteLimit)
        var lines: [BackwardLineReader.Line] = []
        while let line = try reader.olderLine() { lines.append(line) }
        #expect(reader.hasReachedStart)
        #expect(reader.position == 0)
        return lines
    }

    func whole(_ text: String) -> BackwardLineReader.Line {
        .whole(Array(text.utf8))
    }

    @Test func linesComeFromTheEndBackToTheStart() throws {
        #expect(try lines(of: Array("a\nbb\n\nccc".utf8), lineByteLimit: 10) == [whole("ccc"), whole(""), whole("bb"), whole("a")])
        #expect(try lines(of: Array("a\n".utf8), lineByteLimit: 10) == [whole(""), whole("a")])
        #expect(try lines(of: [], lineByteLimit: 10) == [whole("")])
    }

    @Test func aLineOverTheLimitGivesItsStartAndLength() throws {
        let long = String(repeating: "x", count: 200_000)
        #expect(try lines(of: Array("short\n\(long)\nlast\n".utf8), lineByteLimit: 10) == [
            whole(""), whole("last"), .tooLong(start: Array(long.utf8.prefix(16 * 1024)), byteCount: 200_000), whole("short"),
        ])
        #expect(try lines(of: Array("\(long)\nb".utf8), lineByteLimit: 150_000) == [
            whole("b"), .tooLong(start: Array(long.utf8.prefix(16 * 1024)), byteCount: 200_000),
        ])
        #expect(try lines(of: Array("\(long)\nb".utf8), lineByteLimit: 1_000) == [
            whole("b"), .tooLong(start: Array(long.utf8.prefix(16 * 1024)), byteCount: 200_000),
        ])
    }

    @Test func randomLinesComeBackInReverseOrder() throws {
        var generator = SeededGenerator(seed: 0x11E5)
        var expected: [BackwardLineReader.Line] = []
        var text: [UInt8] = []
        for index in 0..<300 {
            let length = index % 50 == 0 ? Int.random(in: 0...300_000, using: &generator) : Int.random(in: 0...3_000, using: &generator)
            let line = [UInt8](repeating: UInt8(ascii: "a") + UInt8(index % 26), count: length)
            text += line + [UInt8(ascii: "\n")]
            expected.append(length > 100_000 ? .tooLong(start: Array(line.prefix(16 * 1024)), byteCount: length) : .whole(line))
        }
        #expect(try lines(of: text, lineByteLimit: 100_000) == [whole("")] + expected.reversed())
    }
}
