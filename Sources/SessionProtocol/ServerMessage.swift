import Foundation

/// A message from the session process to a client.
public enum ServerMessage: Codable, Equatable, Sendable {
    /// Always first. Carries the protocol version of the session process.
    case hello(protocolVersion: Int, capabilities: ServerCapabilities? = nil)
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
    /// `resize` or `attach`, or the session confirms the client's own resize.
    /// The `output` after it is for the new size.
    ///
    /// `keepsCursorAtLineStart` is true when the size comes where a shell
    /// has erased its lines. A client with a copy of the screen then resizes
    /// it with `Terminal.resize(to:keeping:)` and `.cursorRow`, as the
    /// session does. `promptRowsAboveCursor` comes when the shell has not
    /// answered the size in time: the client then resizes with
    /// `.promptRows(aboveCursor:)` and this number. Both fields are optional,
    /// so they stay inside protocol version 1.
    case sizeChanged(SessionSize, keepsCursorAtLineStart: Bool? = nil, promptRowsAboveCursor: Int? = nil)
    /// The text of a session's screen.
    case screen(text: String)
    /// The program ended. The connection closes after this message.
    case exited(SessionExit)
    /// The request worked and has nothing more to say.
    case acknowledged
    case failure(SessionFailure)
    /// A question for the user. Only a connection that asked with
    /// `receiveApprovalQuestions` receives one.
    case approvalQuestion(ApprovalQuestion)
    /// The question has ended: an answer came, its time limit passed, or the
    /// program that asked left. Every connection that holds it receives this.
    case approvalQuestionEnded(identifier: UUID)
    /// A new session, or new facts of a session. Only a connection that
    /// asked with `receiveSessionChanges` receives it.
    case sessionChanged(SessionSummary)
    /// The session has ended and left the list. Only a connection that
    /// asked with `receiveSessionChanges` receives it.
    case sessionEnded(identifier: UUID)
    /// Every project: those with a folder in the user's order, then those
    /// whose folder this Mac does not know. The answer to `listProjects`,
    /// and on a connection that asked with `receiveSessionChanges`, the
    /// whole new list after each change.
    case projectList([ProjectSummary])
    /// The answer to `addProject`: the new project, last among the
    /// projects with a folder.
    case projectAdded(ProjectSummary)
    /// Every setting, in a fixed order. The answer to `listSettings`, and
    /// on a connection that asked with `receiveSessionChanges`, the whole
    /// new list after each change.
    case settingList([SettingSummary])
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

extension ServerMessage {
    /// The name of the message in the protocol, without its fields. An
    /// error names a message by this, because its fields can be large and
    /// can hold anything, such as a whole screen.
    var name: String {
        switch self {
        case .hello: "hello"
        case .sessionCreated: "sessionCreated"
        case .sessionList: "sessionList"
        case .attached: "attached"
        case .snapshot: "snapshot"
        case .output: "output"
        case .sizeChanged: "sizeChanged"
        case .screen: "screen"
        case .exited: "exited"
        case .acknowledged: "acknowledged"
        case .failure: "failure"
        case .approvalQuestion: "approvalQuestion"
        case .approvalQuestionEnded: "approvalQuestionEnded"
        case .sessionChanged: "sessionChanged"
        case .sessionEnded: "sessionEnded"
        case .projectList: "projectList"
        case .projectAdded: "projectAdded"
        case .settingList: "settingList"
        }
    }
}
