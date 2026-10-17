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
