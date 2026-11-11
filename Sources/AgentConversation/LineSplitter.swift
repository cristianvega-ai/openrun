/// Splits an agent's output into lines, as the bytes come in pieces of any
/// size, with a limit on the length of one line.
///
/// An agent writes one JSON object on each line. A piece can end inside a
/// line, so the start of a line waits for its end. A line can be many
/// megabytes, so a line past the limit is not kept: only its start and its
/// length remain, and the next line is read as usual.
public struct LineSplitter: Sendable {
    public enum Piece: Sendable, Hashable {
        /// A whole line, without its line end.
        case line([UInt8])
        /// A line longer than the limit: its start and its length.
        case tooLong(start: [UInt8], byteCount: Int)
        /// The rest of the output after the last line end, when the output
        /// ended: its start and its length.
        case cutShort(start: [UInt8], byteCount: Int)
    }

    public let lineByteLimit: Int
    private var buffer: [UInt8] = []
    /// Set while the rest of a line that is too long passes.
    private var skippedStart: [UInt8]?
    private var skippedByteCount = 0

    public init(lineByteLimit: Int) {
        self.lineByteLimit = max(1, lineByteLimit)
    }

    /// Takes the next bytes and returns the lines that they complete.
    public mutating func append(_ bytes: some Collection<UInt8>) -> [Piece] {
        var pieces: [Piece] = []
        var rest = bytes[...]
        while let lineEnd = rest.firstIndex(of: UInt8(ascii: "\n")) {
            take(rest[..<lineEnd])
            pieces.append(endLine())
            rest = rest[rest.index(after: lineEnd)...]
        }
        take(rest)
        return pieces
    }

    /// Ends the output. Returns the bytes after the last line end, if any.
    public mutating func finish() -> Piece? {
        guard skippedStart != nil || !buffer.isEmpty else { return nil }
        let start = skippedStart ?? Array(buffer.prefix(SourceLine.byteLimit))
        let count = skippedStart == nil ? buffer.count : skippedByteCount
        reset()
        return .cutShort(start: start, byteCount: count)
    }

    private mutating func take(_ part: some Collection<UInt8>) {
        if skippedStart != nil {
            skippedByteCount += part.count
            return
        }
        buffer.append(contentsOf: part)
        if buffer.count > lineByteLimit {
            skippedStart = Array(buffer.prefix(SourceLine.byteLimit))
            skippedByteCount = buffer.count
            buffer = []
        }
    }

    private mutating func endLine() -> Piece {
        defer { reset() }
        if let start = skippedStart { return .tooLong(start: start, byteCount: skippedByteCount) }
        return .line(buffer)
    }

    private mutating func reset() {
        buffer = []
        skippedStart = nil
        skippedByteCount = 0
    }
}
