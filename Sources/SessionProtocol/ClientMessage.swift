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
    ///
    /// `waitsForOutputRoom` asks the session to pause output when this
    /// client falls behind. The output queue stays bounded, and a client
    /// that does not take enough output still loses its connection.
    case attach(identifier: UUID, size: SessionSize, relaysRawOutput: Bool? = nil, receivesSizeChanges: Bool? = nil, waitsForOutputRoom: Bool? = nil)
    /// Keys for the attached session. Sent as a raw `input` frame.
    case input(Data)
    /// The size of the attached client. The last client to resize wins, and
    /// the other clients that asked receive `sizeChanged`. A client may ask
    /// for its own ordered `sizeChanged` with `requestsConfirmation`.
    case resize(SessionSize, requestsConfirmation: Bool? = nil)
    /// Leaves the session running and closes this connection.
    case detach

    // Approval questions, on a connection that stays open.

    /// Asks for the approval questions. Only the signed app outside every
    /// session gets them. Answer: `acknowledged`, then each
    /// `approvalQuestion` and `approvalQuestionEnded`.
    case receiveApprovalQuestions
    /// The user's answer to one question. No message answers it.
    case answerApprovalQuestion(identifier: UUID, allows: Bool)

    // The facts of the sessions.

    /// Asks for every change of the sessions, on a connection that stays
    /// open. Answer: `sessionList`, then each `sessionChanged` and
    /// `sessionEnded`. The connection takes no other request after it.
    ///
    /// With `includesThreads`, the client also gets `threadList` after the
    /// settings, and then `threadChanged` and `threadEnded`. A client that
    /// leaves it out never gets a message of the threads (decision of
    /// 2026-10-19).
    case receiveSessionChanges(includesThreads: Bool? = nil)
    /// Gives a session a name, or removes it with `nil`. Answer:
    /// `acknowledged`. A program in a session may name only its own.
    case renameSession(identifier: UUID, name: String?)
    /// Raises the alert of a session with a text. Answer: `acknowledged`.
    /// A program in a session may alert only its own.
    case raiseSessionAlert(identifier: UUID, text: String)
    /// Ends the alert of a session. Answer: `acknowledged`. A program in a
    /// session may clear only its own.
    case clearSessionAlert(identifier: UUID)

    // The projects. Any client may change them, because they type into no
    // session and read none.

    /// Answer: `projectList`.
    case listProjects
    /// Adds a folder as a project at the end of the list. A relative folder
    /// starts at `currentFolder`, the folder of the client, and `~` is the
    /// home folder. Answer: `projectAdded`.
    case addProject(folder: String, name: String?, currentFolder: String?)
    /// Removes a project. Its sessions keep running. Answer: `acknowledged`.
    case removeProject(identifier: UUID)
    /// Gives a project a name, or removes the name with `nil` or an empty
    /// name. Answer: `acknowledged`.
    case renameProject(identifier: UUID, name: String?)
    /// Moves a project to `place` in the order, from 0. Answer: `acknowledged`.
    case moveProject(identifier: UUID, place: Int)

    // The settings.

    /// Answer: `settingList`.
    case listSettings
    /// Changes one setting to the value that `text` gives, in the form of
    /// `openrun settings set`. Only OpenRun.app may change a protected
    /// setting. Answer: `acknowledged`.
    case changeSetting(name: String, text: String)

    // Agent threads. Check `capabilities.threads` first. Only a program
    // outside every session and every thread may send these (decision of
    // 2026-11-10).

    /// Makes a thread. `nil` for the model or the permission mode takes the
    /// one of the settings. Answer: `threadCreated`.
    case createThread(agent: String, folder: String, model: String? = nil, permissionMode: String? = nil, name: String? = nil)
    /// Answer: `threadList`.
    case listThreads
    /// Gives a thread a name, or removes it with `nil` or an empty name.
    /// Answer: `acknowledged`.
    case renameThread(identifier: UUID, name: String?)
    /// Changes the model, the permission mode, or both. The agent takes
    /// them at its next start, which comes at once when no turn runs and
    /// else after the turn. A mode outside `permissionModes` of the
    /// summary gets a failure. Answer: `acknowledged`.
    case changeThread(identifier: UUID, model: String? = nil, permissionMode: String? = nil)
    /// Open in Terminal (proposal 6): stops the agent of the thread, and
    /// resumes the conversation with the agent's own program in a new
    /// terminal session. Answer: `sessionCreated`. The thread takes no
    /// message until that session ends.
    case openThreadInTerminal(identifier: UUID, size: SessionSize)
    /// Ends the terminal session of a thread, so the thread takes
    /// messages again. Answer: `acknowledged`.
    case returnThreadFromTerminal(identifier: UUID)
    /// Ends the process of the thread and removes its record. The history
    /// of the agent stays where the agent keeps it. Answer: `acknowledged`.
    case closeThread(identifier: UUID)
    /// Attaches the connection to a thread. Answer: `threadAttached`, the
    /// events that the thread kept, `threadReplayComplete`, and then each
    /// new event. The connection then takes `sendThreadMessage`,
    /// `stopThread` and `detach`.
    case attachThread(identifier: UUID)
    /// Asks for a page of the earlier turns of a thread, from the history
    /// of its agent. `before` is the `before` of the page that the client
    /// has, or nil for the newest page. Answer: the events of whole
    /// turns, oldest first, and then `threadHistoryPage`.
    case readThreadHistory(identifier: UUID, before: Int? = nil)
    /// Sends a message of the user to a thread. It waits behind a turn
    /// that runs. Answer: `threadMessageSent`.
    case sendThreadMessage(identifier: UUID, text: String, images: [ThreadImage]? = nil)
    /// Stops the turn of a thread. Answer: `acknowledged`, also when no
    /// turn runs.
    case stopThread(identifier: UUID)

    // The permission requests of an agent (decision of 2026-11-10).

    /// The permission hook of an agent asks for the user. `request` is
    /// what the agent gave the hook, as it came. Only a program that the
    /// agent of a thread started may send it. The answer comes when the
    /// user answered or the request ended: `toolPermissionAnswer`.
    case requestToolPermission(request: Data)
    /// The answer of the user to a permission request of a thread. Only
    /// OpenRun.app may send it. Answer: `acknowledged`, or a failure when
    /// the request does not wait any more.
    case answerToolPermission(thread: UUID, request: String, allows: Bool, message: String? = nil)
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
        case .output, .snapshot, .threadEvent:
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
        case .receiveApprovalQuestions: "receiveApprovalQuestions"
        case .answerApprovalQuestion: "answerApprovalQuestion"
        case .receiveSessionChanges: "receiveSessionChanges"
        case .renameSession: "renameSession"
        case .raiseSessionAlert: "raiseSessionAlert"
        case .clearSessionAlert: "clearSessionAlert"
        case .listProjects: "listProjects"
        case .addProject: "addProject"
        case .removeProject: "removeProject"
        case .renameProject: "renameProject"
        case .moveProject: "moveProject"
        case .listSettings: "listSettings"
        case .changeSetting: "changeSetting"
        case .createThread: "createThread"
        case .listThreads: "listThreads"
        case .renameThread: "renameThread"
        case .changeThread: "changeThread"
        case .openThreadInTerminal: "openThreadInTerminal"
        case .returnThreadFromTerminal: "returnThreadFromTerminal"
        case .closeThread: "closeThread"
        case .attachThread: "attachThread"
        case .readThreadHistory: "readThreadHistory"
        case .sendThreadMessage: "sendThreadMessage"
        case .stopThread: "stopThread"
        case .requestToolPermission: "requestToolPermission"
        case .answerToolPermission: "answerToolPermission"
        }
    }
}
