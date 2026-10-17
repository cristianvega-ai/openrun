import Foundation

/// A message from a client to the session process.
///
/// A connection starts with `hello`. Then it either does one request and
/// reads one answer, or it attaches to a session and stays open.
public enum ClientMessage: Codable, Equatable, Sendable {
    /// Always first. Carries the protocol version of the client.
    case hello(protocolVersion: Int)

    // One request, one answer.

    /// Starts a session. A `nil` command runs the login shell of the user.
    /// The environment is the client's, so a program starts with the user's
    /// own `PATH` and settings. Answer: `sessionCreated`.
    case createSession(folder: String, command: [String]?, size: SessionSize, environment: [String: String])
    /// Answer: `sessionList`.
    case listSessions
    /// Answer: `screen`.
    case readScreen(identifier: UUID, includeScrollback: Bool)
    /// Types text into a session without attaching. Answer: `acknowledged`.
    case sendText(identifier: UUID, text: String)
    /// Ends the session's program and waits until the session is gone.
    /// Answer: `acknowledged`.
    case killSession(identifier: UUID)

    // A connection that stays open.

    /// Attaches this connection to a session at the given size. Answer:
    /// `attached`, then `snapshot`, then `output` and finally `exited`.
    ///
    /// `relaysRawOutput` says whether the client writes the raw `output` bytes
    /// to a real terminal. That terminal answers the queries in the bytes, so
    /// the session process stays silent while such a client is attached. The
    /// field is optional so that it stays inside protocol version 1: a client
    /// that does not send it, and a client that sends `nil` or `false`, does
    /// not relay, and the session process keeps answering for it.
    ///
    /// `receivesSizeChanges` asks for a `sizeChanged` message each time
    /// another client changes the size of the session. It is optional for
    /// the same reason. A client that does not ask never receives one.
    case attach(identifier: UUID, size: SessionSize, relaysRawOutput: Bool? = nil, receivesSizeChanges: Bool? = nil)
    /// Keys for the attached session. Sent as a raw `input` frame.
    case input(Data)
    /// The size of the attached client. The last client to resize wins, and
    /// the other clients that asked receive `sizeChanged`.
    case resize(SessionSize)
    /// Leaves the session running and closes this connection.
    case detach
}

extension ClientMessage: FramedMessage {
    public func frame() throws -> MessageFrame {
        if case .input(let bytes) = self {
            return MessageFrame(kind: .input, payload: bytes)
        }
        return MessageFrame(kind: .control, payload: try JSONEncoder.messages.encode(self))
    }

    public init(frame: MessageFrame) throws {
        switch frame.kind {
        case .input:
            self = .input(frame.payload)
        case .control:
            self = try JSONDecoder.messages.decodeControlMessage(ClientMessage.self, from: frame.payload)
            // Keys always travel as raw frames, so a JSON copy is a mistake.
            if case .input = self {
                throw SessionProtocolError.malformedFrame(reason: "input must be a raw frame")
            }
        case .output, .snapshot:
            throw SessionProtocolError.unexpectedMessage(description: "a server frame arrived at the server")
        }
    }
}

extension ClientMessage {
    /// The name of the message in the protocol, without its fields. An
    /// error names a message by this, because its fields come from the peer
    /// and can hold anything, such as text that a user typed.
    var name: String {
        switch self {
        case .hello: "hello"
        case .createSession: "createSession"
        case .listSessions: "listSessions"
        case .readScreen: "readScreen"
        case .sendText: "sendText"
        case .killSession: "killSession"
        case .attach: "attach"
        case .input: "input"
        case .resize: "resize"
        case .detach: "detach"
        }
    }
}
