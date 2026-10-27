import Foundation
import SessionProtocol

/// A connection that is attached to one session. It starts with the
/// snapshot of the terminal of the session.
public final class SessionAttachment: Sendable {
    /// The terminal of the session at the moment of the attach, as the protocol
    /// carries it. `TerminalSnapshot(bytes:)` restores it. Output comes after it.
    public let snapshot: Data
    private let connection: MessageConnection

    init(connection: MessageConnection, snapshot: Data) {
        self.connection = connection
        self.snapshot = snapshot
    }

    /// Sends `attach` and waits for `attached` and the snapshot. A failure in
    /// their place ends the attach before the caller changes anything.
    static func attach(on connection: MessageConnection, to identifier: UUID, size: SessionSize, relaysRawOutput: Bool, receivesSizeChanges: Bool) throws -> SessionAttachment {
        // A flag that is off stays out of the message. Every session process
        // reads that as off, and the tool sends the message that it sent before.
        let message = ClientMessage.attach(identifier: identifier, size: size, relaysRawOutput: relaysRawOutput ? true : nil, receivesSizeChanges: receivesSizeChanges ? true : nil)
        try SessionConnectionError.wrapping { try connection.send(message) }
        for _ in 0..<2 {
            switch try SessionConnectionError.wrapping({ try connection.receive(ServerMessage.self) }) {
            case .attached:
                continue
            case .snapshot(let bytes):
                return SessionAttachment(connection: connection, snapshot: bytes)
            case .failure(let failure):
                throw SessionConnectionError.requestFailed(failure)
            default:
                throw SessionConnectionError.unexpectedAttachAnswer
            }
        }
        throw SessionConnectionError.missingSnapshot
    }
}
