import Foundation
import SessionProtocol
import Synchronization

/// The connection on which the app receives approval questions and sends
/// the user's answers. The session process opens it only for OpenRun.app,
/// signed and outside every session.
public final class ApprovalQuestionReceiver: Sendable {
    /// What the session process tells the app. `closed` and `failed` come last.
    public enum Event: Equatable, Sendable {
        case question(ApprovalQuestion)
        /// The question ended, so the app stops showing it.
        case ended(UUID)
        case closed
        case failed(SessionConnectionError)
    }

    private let connection: MessageConnection
    private let isReceiving = Atomic<Bool>(false)

    private init(connection: MessageConnection) {
        self.connection = connection
    }

    /// Asks for the questions, and returns once the session process agrees.
    static func open(on connection: MessageConnection) throws -> ApprovalQuestionReceiver {
        try SessionConnectionError.wrapping { try connection.send(ClientMessage.receiveApprovalQuestions) }
        switch try SessionConnectionError.wrapping({ try connection.receive(ServerMessage.self) }) {
        case .acknowledged: return ApprovalQuestionReceiver(connection: connection)
        case .failure(let failure): throw SessionConnectionError.requestFailed(failure)
        case nil: throw SessionConnectionError.connectionClosed
        default: throw SessionConnectionError.unexpectedAnswer(request: "receiveApprovalQuestions")
        }
    }

    /// Sends the user's answer to one question.
    public func answer(_ identifier: UUID, allows: Bool) throws {
        try SessionConnectionError.wrapping {
            try connection.send(ClientMessage.answerApprovalQuestion(identifier: identifier, allows: allows))
        }
    }

    /// Ends the connection. The session process then ends each question that
    /// only this connection held.
    public func shutdown() {
        connection.shutdown()
    }

    /// Starts the thread that hands each event to `handler` in order. Only
    /// the first call starts a thread.
    public func startReceiving(_ handler: @escaping @Sendable (Event) -> Void) {
        guard !isReceiving.exchange(true, ordering: .acquiringAndReleasing) else { return }
        let receiver = Thread { [self] in
            while true {
                let message: ServerMessage?
                do {
                    message = try connection.receive(ServerMessage.self)
                } catch {
                    handler(.failed(.protocolFailure(error as? SessionProtocolError ?? .malformedFrame(reason: "\(error)"))))
                    return
                }
                switch message {
                case .approvalQuestion(let question): handler(.question(question))
                case .approvalQuestionEnded(let identifier): handler(.ended(identifier))
                case nil: return handler(.closed)
                default: continue
                }
            }
        }
        receiver.name = "approval.receiver"
        receiver.start()
    }
}

extension SessionClient {
    /// Turns the connection into the one that receives approval questions.
    /// The client takes no more requests.
    public func receiveApprovalQuestions() throws -> ApprovalQuestionReceiver {
        try ApprovalQuestionReceiver.open(on: connection)
    }
}
