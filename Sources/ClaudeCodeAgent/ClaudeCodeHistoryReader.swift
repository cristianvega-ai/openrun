import AgentConversation
import Foundation

/// Reads the history file of a Claude Code conversation in pages, from the
/// newest line back to the oldest.
///
/// It reads the file in place and copies it nowhere, because the file
/// holds the system prompt and the identifiers of the account. Claude Code
/// can append to the file while it is read, so the reader takes the size
/// at its start, and leaves out a last line without its line end. Memory
/// stays bounded for a file of any size: one page, and one line up to the
/// line limit.
public final class ClaudeCodeHistoryReader {
    public static let defaultPageByteCount = 256 * 1024
    /// A page of whole turns stops in a turn that is longer than this
    /// many pages, so one very long turn cannot fill the memory.
    static let longestTurnInPages: UInt64 = 8

    private let file: FileHandle
    private let lines: BackwardLineReader

    /// - Parameter before: The `cursor` of an earlier reader. The new
    ///   reader gives the lines before it, so a client can ask for one
    ///   page at a time and the reader keeps no state between two pages.
    ///   Nil starts at the end of the file.
    public init(fileURL: URL, before: UInt64? = nil, lineByteLimit: Int = ClaudeCodeOutputDecoder.defaultLineByteLimit) throws {
        file = try FileHandle(forReadingFrom: fileURL)
        let size = try file.seekToEnd()
        lines = BackwardLineReader(file: file, end: min(before ?? size, size), lineByteLimit: lineByteLimit)
        // The last line has no line end while Claude Code writes it.
        if before == nil { _ = try lines.olderLine() }
    }

    deinit {
        try? file.close()
    }

    /// Whether the oldest line was read.
    public var hasReachedStart: Bool { lines.hasReachedStart }

    /// Where the lines that the reader gave start. A later reader takes
    /// it as `before`.
    public var cursor: UInt64 { lines.position }

    /// The events of whole turns before the last page, oldest first: the
    /// lines of about `pageByteCount` bytes, and then the lines back to
    /// the message of the user that starts their turn. So a page does not
    /// start in the middle of a turn, unless the turn is very long.
    public func previousTurns(pageByteCount: Int = defaultPageByteCount) throws -> [ConversationEvent] {
        var pages: [[ConversationEvent]] = []
        let (end, page) = (lines.position, UInt64(max(1, pageByteCount)))
        while end - lines.position < page * Self.longestTurnInPages, let line = try lines.olderLine() {
            let events = Self.events(of: line)
            pages.append(events)
            let startsTurn = events.contains { if case .userMessage = $0.kind { true } else { false } }
            if startsTurn, end - lines.position >= page { break }
        }
        return pages.reversed().flatMap(\.self)
    }

    /// The events of about `pageByteCount` bytes of lines before the last
    /// page, oldest first. A page can have no events, when its lines are of
    /// kinds that a chat does not show. Empty at the start of the file.
    public func previousPage(pageByteCount: Int = defaultPageByteCount) throws -> [ConversationEvent] {
        var pages: [[ConversationEvent]] = []
        let end = lines.position
        while end - lines.position < UInt64(max(1, pageByteCount)), let line = try lines.olderLine() {
            pages.append(Self.events(of: line))
        }
        return pages.reversed().flatMap(\.self)
    }

    /// The events of the lines that Claude Code wrote after `offset`, an
    /// earlier size of the file: the turns that the user made in a
    /// terminal (proposal 6). At most the last `byteLimit` bytes are read.
    public static func events(inFileAt fileURL: URL, after offset: UInt64, byteLimit: Int = 4 * 1024 * 1024) throws -> [ConversationEvent] {
        let reader = try ClaudeCodeHistoryReader(fileURL: fileURL)
        var pages: [[ConversationEvent]] = []
        let end = reader.lines.position
        while reader.lines.position > offset, end - reader.lines.position < UInt64(byteLimit), let line = try reader.lines.olderLine() {
            pages.append(events(of: line))
        }
        return pages.reversed().flatMap(\.self)
    }

    private static func events(of line: BackwardLineReader.Line) -> [ConversationEvent] {
        switch line {
        case .whole(let bytes):
            guard let value = try? JSONValue(decoding: Data(bytes)) else { return [] }
            let source = SourceLine(bytes: bytes)
            return ClaudeCodeHistoryLine.events(value).map { ConversationEvent($0, sourceLine: source) }
        case .tooLong(let start, let byteCount):
            let source = SourceLine(text: BoundedText.prefix(of: start, byteLimit: SourceLine.byteLimit), byteCount: byteCount)
            return [ConversationEvent(.unknown(UnknownLine(reason: .tooLong, text: source.text, byteCount: byteCount)), sourceLine: source)]
        }
    }
}
