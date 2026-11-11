import AgentConversation
import Foundation

/// Turns the standard output of the app-server, in pieces of any size,
/// into messages.
///
/// Each message keeps the start of its line. A line that is not a message,
/// that is longer than the limit, or that the output cuts short gives an
/// unreadable line, and the next line is read as usual.
struct CodexMessageReader: Sendable {
    enum Incoming: Sendable, Hashable {
        case message(CodexMessage, SourceLine)
        case unreadable(UnknownLine, SourceLine)
    }

    /// The longest line that the reader reads. A page of history or the
    /// output of a command comes as one line, and the JSON value of a line
    /// takes a few times its size in memory.
    static let defaultLineByteLimit = 16 * 1024 * 1024

    private var splitter: LineSplitter

    init(lineByteLimit: Int = defaultLineByteLimit) {
        splitter = LineSplitter(lineByteLimit: lineByteLimit)
    }

    /// Takes the next bytes and returns the messages of the lines that
    /// they complete.
    mutating func read(_ bytes: some Collection<UInt8>) -> [Incoming] {
        splitter.append(bytes).map(Self.incoming)
    }

    /// Ends the output. A line that the output cut short is unreadable.
    mutating func finish() -> [Incoming] {
        splitter.finish().map { [Self.incoming($0)] } ?? []
    }

    private static func incoming(_ piece: LineSplitter.Piece) -> Incoming {
        switch piece {
        case .line(let bytes):
            let source = SourceLine(bytes: bytes)
            guard let value = try? JSONValue(decoding: Data(bytes)), value.object != nil else {
                return unreadable(.notJSON, kind: nil, source)
            }
            guard let message = CodexMessage(value) else { return unreadable(.unknownKind, kind: value["method"]?.string, source) }
            return .message(message, source)
        case .tooLong(let start, let byteCount):
            return unreadable(.tooLong, kind: nil, SourceLine(text: BoundedText.prefix(of: start, byteLimit: SourceLine.byteLimit), byteCount: byteCount))
        case .cutShort(let start, let byteCount):
            return unreadable(.cutShort, kind: nil, SourceLine(text: BoundedText.prefix(of: start, byteLimit: SourceLine.byteLimit), byteCount: byteCount))
        }
    }

    private static func unreadable(_ reason: UnknownLine.Reason, kind: String?, _ source: SourceLine) -> Incoming {
        .unreadable(UnknownLine(reason: reason, kind: kind, text: source.text, byteCount: source.byteCount), source)
    }
}
