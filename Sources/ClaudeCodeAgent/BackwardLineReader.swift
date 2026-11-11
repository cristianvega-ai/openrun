import AgentConversation
import Foundation

/// Reads the lines of a file from the end back to the start, with a limit
/// on the length of one line.
///
/// Memory holds at most two times the limit, whatever the size of the
/// file. A line over the limit gives only its first bytes and its length.
final class BackwardLineReader {
    enum Line: Equatable {
        /// A line without its line end.
        case whole([UInt8])
        case tooLong(start: [UInt8], byteCount: Int)
    }

    private static let chunkByteCount = 64 * 1024

    private let file: FileHandle
    private let lineByteLimit: Int
    /// The end of the next line to read.
    private(set) var position: UInt64
    /// The bytes from `bufferStart` to `position`: read, and not yet given.
    private var buffer: [UInt8] = []
    private var bufferStart: UInt64
    /// Whether the first line of the file was given.
    private(set) var hasReachedStart = false

    /// Reads the lines that end before `end`. The bytes after the last
    /// line end before `end` are the first line that `olderLine` gives.
    init(file: FileHandle, end: UInt64, lineByteLimit: Int) {
        self.file = file
        self.lineByteLimit = max(1, lineByteLimit)
        position = end
        bufferStart = end
    }

    /// The line that ends at `position`, without its line end, or nil
    /// after the first line of the file.
    func olderLine() throws -> Line? {
        while !hasReachedStart {
            if let lineEnd = buffer.lastIndex(of: UInt8(ascii: "\n")) {
                let result = line(buffer[(lineEnd + 1)...])
                buffer.removeSubrange(lineEnd...)
                position = bufferStart + UInt64(lineEnd)
                return result
            }
            if bufferStart == 0 {
                hasReachedStart = true
                defer { buffer = []; position = 0 }
                return line(buffer[...])
            }
            if buffer.count > lineByteLimit { return try skipLongLine() }
            try readChunk(byteCount: max(Self.chunkByteCount, buffer.count))
        }
        return nil
    }

    /// The last chunk can bring the start of a line over the limit.
    private func line(_ bytes: ArraySlice<UInt8>) -> Line {
        guard bytes.count > lineByteLimit else { return .whole(Array(bytes)) }
        return .tooLong(start: Array(bytes.prefix(SourceLine.byteLimit)), byteCount: bytes.count)
    }

    /// Finds the start of a line over the limit without keeping its bytes,
    /// and reads only its first bytes.
    private func skipLongLine() throws -> Line {
        let lineEnd = position
        buffer = []
        position = bufferStart
        while bufferStart > 0, buffer.lastIndex(of: UInt8(ascii: "\n")) == nil {
            buffer = []
            position = bufferStart
            try readChunk(byteCount: Self.chunkByteCount)
        }
        // The line starts after the last line end in the buffer, or at 0.
        let lineStart = buffer.lastIndex(of: UInt8(ascii: "\n")).map { bufferStart + UInt64($0) + 1 } ?? 0
        try file.seek(toOffset: lineStart)
        let start = Array(try file.read(upToCount: SourceLine.byteLimit) ?? Data())
        if let newline = buffer.lastIndex(of: UInt8(ascii: "\n")) {
            buffer.removeSubrange(newline...)
            position = bufferStart + UInt64(newline)
        } else {
            buffer = []
            position = 0
            hasReachedStart = true
        }
        return .tooLong(start: start, byteCount: Int(lineEnd - lineStart))
    }

    /// Puts the bytes before `bufferStart` in front of the buffer.
    private func readChunk(byteCount: Int) throws {
        let start = bufferStart - min(bufferStart, UInt64(byteCount))
        try file.seek(toOffset: start)
        let chunk = try file.read(upToCount: Int(bufferStart - start)) ?? Data()
        buffer.insert(contentsOf: chunk, at: 0)
        bufferStart = start
    }
}
