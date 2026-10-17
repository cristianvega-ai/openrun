import Foundation

/// A message from the session process to a client.
public enum ServerMessage: Codable, Equatable, Sendable {
    /// Always first. Carries the protocol version of the session process.
    case hello(protocolVersion: Int)
    case sessionCreated(SessionSummary)
    case sessionList([SessionSummary])
    /// The client is attached. A `snapshot` follows at once.
    case attached(SessionSummary)
    /// The state of the terminal at the moment of attaching. Sent as a raw
    /// `snapshot` frame. Every `output` after it came after the snapshot.
    case snapshot(Data)
    /// Bytes the program wrote. Sent as a raw `output` frame.
    case output(Data)
    /// Another client changed the size of the attached session with its
    /// `resize` or `attach`. Only a client that asked in `attach` receives
    /// this. The `output` after it is for the new size.
    case sizeChanged(SessionSize)
    /// The text of a session's screen.
    case screen(text: String)
    /// The program ended. The connection closes after this message.
    case exited(SessionExit)
    /// The request worked and has nothing more to say.
    case acknowledged
    case failure(SessionFailure)
}

extension ServerMessage: FramedMessage {
    public func frame() throws -> MessageFrame {
        switch self {
        case .output(let bytes):
            MessageFrame(kind: .output, payload: bytes)
        case .snapshot(let bytes):
            MessageFrame(kind: .snapshot, payload: bytes)
        default:
            MessageFrame(kind: .control, payload: try JSONEncoder.messages.encode(self))
        }
    }

    public init(frame: MessageFrame) throws {
        switch frame.kind {
        case .output:
            self = .output(frame.payload)
        case .snapshot:
            self = .snapshot(frame.payload)
        case .control:
            self = try JSONDecoder.messages.decodeControlMessage(ServerMessage.self, from: frame.payload)
            switch self {
            case .output, .snapshot:
                throw SessionProtocolError.malformedFrame(reason: "terminal bytes must be a raw frame")
            default:
                break
            }
        case .input:
            throw SessionProtocolError.unexpectedMessage(description: "a client frame arrived at the client")
        }
    }
}
