import Foundation

/// One unit on the socket: a length, a kind, and a payload.
///
/// ```
/// +----------------------+-----------+----------------------+
/// | length: 4 bytes, big | kind: 1   | payload: length - 1  |
/// | endian, counts kind  | byte      | bytes                |
/// | and payload          |           |                      |
/// +----------------------+-----------+----------------------+
/// ```
///
/// Control messages are JSON because they are small, rare and easy to read in
/// a log. Terminal bytes travel raw, because they are frequent and large, and
/// JSON would make them bigger and slower.
public struct MessageFrame: Equatable, Sendable {
    public enum Kind: UInt8, Sendable {
        /// A JSON message.
        case control = 1
        /// Bytes that the program wrote. Server to client.
        case output = 2
        /// Bytes for the program to read. Client to server.
        case input = 3
        /// A terminal snapshot. Server to client.
        case snapshot = 4
    }

    /// The version of the protocol. Both sides send it in their first
    /// message. Raise it when a change would confuse an older program.
    public static let protocolVersion = 1

    /// The number of bytes before the kind: the length field.
    public static let lengthFieldSize = 4

    /// The largest payload a frame may carry. The limit stops a broken or
    /// hostile peer from making the receiver allocate gigabytes. A snapshot
    /// of a wide terminal with a full, colorful scrollback can be larger. The
    /// session process then sends less scrollback, so the snapshot fits.
    public static let maximumPayloadLength = 64 * 1024 * 1024

    public var kind: Kind
    public var payload: Data

    public init(kind: Kind, payload: Data) {
        self.kind = kind
        self.payload = payload
    }

    /// The bytes to write to the socket.
    public func encoded() throws -> Data {
        guard payload.count <= Self.maximumPayloadLength else {
            throw SessionProtocolError.frameTooLarge(length: payload.count, limit: Self.maximumPayloadLength)
        }
        var bytes = Data(capacity: Self.lengthFieldSize + 1 + payload.count)
        withUnsafeBytes(of: UInt32(payload.count + 1).bigEndian) { bytes.append(contentsOf: $0) }
        bytes.append(kind.rawValue)
        bytes.append(payload)
        return bytes
    }

    /// Reads the length field and returns how many bytes follow it. The check
    /// happens before the caller allocates anything.
    public static func bodyLength(fromLengthField field: Data) throws -> Int {
        guard field.count == lengthFieldSize else {
            throw SessionProtocolError.malformedFrame(reason: "the length field has \(field.count) bytes")
        }
        let length = field.reduce(0) { ($0 << 8) | Int($1) }
        guard length >= 1 else {
            throw SessionProtocolError.malformedFrame(reason: "the length is zero, so the kind is missing")
        }
        guard length - 1 <= maximumPayloadLength else {
            throw SessionProtocolError.frameTooLarge(length: length - 1, limit: maximumPayloadLength)
        }
        return length
    }

    /// Splits the bytes after the length field into kind and payload.
    public init(body: Data) throws {
        guard let first = body.first else {
            throw SessionProtocolError.malformedFrame(reason: "the kind byte is missing")
        }
        self.kind = try Self.kind(fromByte: first)
        self.payload = body.dropFirst()
    }

    /// The kind that a kind byte names. A receiver reads the kind before it
    /// decides whether a frame has room, so it checks the byte on its own.
    static func kind(fromByte byte: UInt8) throws -> Kind {
        guard let kind = Kind(rawValue: byte) else {
            throw SessionProtocolError.malformedFrame(reason: "the kind byte \(byte) is unknown")
        }
        return kind
    }
}

extension JSONEncoder {
    static var messages: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        // Sorted keys keep logs and tests stable.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var messages: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    /// Decodes the JSON of a control message.
    ///
    /// A payload that holds no message of the protocol throws
    /// `SessionProtocolError.malformedFrame`, with a reason that names the
    /// problem in the words of the protocol. The reason never quotes the
    /// payload. The peer wrote it, and it can hold anything, such as escape
    /// sequences that would drive the terminal that shows the error.
    func decodeControlMessage<Message: Decodable>(_ type: Message.Type, from payload: Data) throws -> Message {
        do {
            return try decode(type, from: payload)
        } catch let error as DecodingError {
            throw SessionProtocolError.malformedFrame(reason: Self.reason(for: error, payload: payload))
        }
    }

    /// Takes any JSON and keeps nothing, to tell JSON that cannot be read
    /// from JSON with a value that does not fit.
    private struct AnyValue: Decodable {
        init(from decoder: any Decoder) {}
    }

    private static func reason(for error: DecodingError, payload: Data) -> String {
        switch error {
        case .dataCorrupted(let context) where context.codingPath.isEmpty:
            // The decoder reports a number that does not fit its type, such
            // as 999999 for a UInt16, without a path, as it reports bad JSON.
            (try? JSONDecoder().decode(AnyValue.self, from: payload)) != nil
                ? "a value in the control message is out of range"
                : "the control message is not valid JSON, or nests too deeply"
        case .dataCorrupted(let context):
            "the field \(fieldName(context.codingPath)) holds a value that is out of range or in the wrong form"
        case .keyNotFound(let key, let context):
            "the field \(fieldName(context.codingPath + [key])) is missing"
        case .valueNotFound(_, let context):
            "the field \(fieldName(context.codingPath)) is null"
        case .typeMismatch(_, let context) where context.codingPath.isEmpty:
            "the control message is not a JSON object with the name of one message of the protocol"
        case .typeMismatch(_, let context):
            "the field \(fieldName(context.codingPath)) has the wrong type"
        @unknown default:
            "the control message cannot be decoded"
        }
    }

    /// The path of a field, such as `createSession.size.columns`. The names
    /// of the protocol pass as they are. A name that the peer chose, such as
    /// the name of an environment variable, passes only when it is plain
    /// letters, digits and underscores.
    private static func fieldName(_ path: [any CodingKey]) -> String {
        var text = ""
        for key in path {
            let name = key.stringValue
            let isPlain = !name.isEmpty && name.count <= 64 && name.unicodeScalars.allSatisfy { scalar in
                ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_"
            }
            if isPlain {
                text += (text.isEmpty ? "" : ".") + name
            } else if let index = key.intValue {
                text += "[\(index)]"
            } else {
                text += (text.isEmpty ? "" : ".") + "(a name)"
            }
        }
        return text.isEmpty ? "(the message)" : text
    }
}
