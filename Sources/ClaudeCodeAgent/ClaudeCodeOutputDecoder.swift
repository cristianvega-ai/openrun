import AgentConversation
import Foundation

/// Turns the standard output of Claude Code, in pieces of any size, into
/// conversation events.
///
/// Each line gives at least one event, and each event carries the start of
/// its line. A line that is not JSON, of a kind that this version does not
/// know, or longer than the limit gives an unknown event, and the next
/// line is read as usual.
public struct ClaudeCodeOutputDecoder: Sendable {
    /// The longest line that the decoder reads. A Write call of a large
    /// file comes as one line, and the JSON value of a line takes a few
    /// times its size in memory.
    public static let defaultLineByteLimit = 16 * 1024 * 1024

    private var splitter: LineSplitter
    private var decoder = ClaudeCodeLineDecoder()

    public init(lineByteLimit: Int = defaultLineByteLimit) {
        splitter = LineSplitter(lineByteLimit: lineByteLimit)
    }

    /// Takes the next bytes and returns the events of the lines that they
    /// complete.
    public mutating func decode(_ bytes: some Collection<UInt8>) -> [ConversationEvent] {
        splitter.append(bytes).flatMap { events(of: $0) }
    }

    /// Ends the output. A line that the output cut short gives an unknown
    /// event.
    public mutating func finish() -> [ConversationEvent] {
        splitter.finish().map { events(of: $0) } ?? []
    }

    private mutating func events(of piece: LineSplitter.Piece) -> [ConversationEvent] {
        switch piece {
        case .line(let bytes):
            let source = SourceLine(bytes: bytes)
            guard let line = try? JSONValue(decoding: Data(bytes)), line.object != nil else {
                return [unknown(.notJSON, kind: nil, source)]
            }
            guard let kinds = decoder.decode(line), !kinds.isEmpty else {
                let kind = [line["type"]?.string, line["subtype"]?.string].compactMap(\.self).joined(separator: "/")
                return [unknown(.unknownKind, kind: kind.isEmpty ? nil : kind, source)]
            }
            return kinds.map { ConversationEvent($0, sourceLine: source) }
        case .tooLong(let start, let byteCount):
            return [unknown(.tooLong, kind: nil, SourceLine(text: BoundedText.prefix(of: start, byteLimit: SourceLine.byteLimit), byteCount: byteCount))]
        case .cutShort(let start, let byteCount):
            return [unknown(.cutShort, kind: nil, SourceLine(text: BoundedText.prefix(of: start, byteLimit: SourceLine.byteLimit), byteCount: byteCount))]
        }
    }

    private func unknown(_ reason: UnknownLine.Reason, kind: String?, _ source: SourceLine) -> ConversationEvent {
        ConversationEvent(.unknown(UnknownLine(reason: reason, kind: kind, text: source.text, byteCount: source.byteCount)), sourceLine: source)
    }
}
