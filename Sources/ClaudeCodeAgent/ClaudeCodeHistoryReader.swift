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

    private let file: FileHandle
    private let lines: BackwardLineReader

    public init(fileURL: URL, lineByteLimit: Int = ClaudeCodeOutputDecoder.defaultLineByteLimit) throws {
        file = try FileHandle(forReadingFrom: fileURL)
        lines = BackwardLineReader(file: file, end: try file.seekToEnd(), lineByteLimit: lineByteLimit)
        // The last line has no line end while Claude Code writes it.
        _ = try lines.olderLine()
    }

    deinit {
        try? file.close()
    }

    /// Whether the oldest line was read.
    public var hasReachedStart: Bool { lines.hasReachedStart }

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
