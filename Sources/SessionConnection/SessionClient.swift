import Darwin
import Foundation
import SessionLaunch
import SessionProtocol

/// A connection to the session process, after the greeting.
public struct SessionClient: Sendable {
    let connection: MessageConnection
    public let capabilities: ServerCapabilities

    /// Starts the session process when nothing listens on the socket.
    typealias Wake = () throws(SessionWakeFailure) -> Void

    /// Connects to the session process on the socket, and greets it. On
    /// the default socket, launchd starts the session process when needed.
    public init(location: SocketLocation) throws {
        try self.init(location: location, wake: Self.launchAgentWake(for: location))
    }

    /// Like `init(location:)`, for a caller that cannot wait without end for
    /// a session process that accepts the connection and never says hello.
    /// Past the limit, it throws `SessionProtocolError.timedOut` inside
    /// `SessionConnectionError.protocolFailure`.
    public init(location: SocketLocation, helloTimeLimit: Duration) throws {
        try self.init(location: location, wake: Self.launchAgentWake(for: location), helloTimeLimit: helloTimeLimit)
    }

    /// Sends one wake when no session process listens, or when the
    /// connection closes before hello, and then connects once more. A
    /// launch agent that ends because it is idle closes such a connection.
    /// A hello that takes too long is no reason for a wake.
    ///
    /// - Parameter wake: Nil for a socket without a launch agent. Tests pass
    ///   their own, because a test cannot register a launch agent.
    /// - Parameter helloTimeLimit: The time that each hello may take. Nil
    ///   waits as long as it takes.
    init(location: SocketLocation, wake: Wake?, helloTimeLimit: Duration? = nil) throws {
        try self.init(wake: wake) {
            try Self(greeting: Self.connect(to: location), within: helloTimeLimit)
        }
    }

    init(wake: Wake?, connect: () throws -> SessionClient) throws {
        do {
            self = try connect()
        } catch let error as SessionConnectionError where wake != nil && Self.meansNoSessionProcess(error) {
            do {
                try wake?()
            } catch {
                throw SessionConnectionError.wakeFailed(error)
            }
            self = try connect()
        }
    }

    /// Only the default socket belongs to the launch agent.
    static func launchAgentWake(for location: SocketLocation) -> Wake? {
        guard location.isDefault else { return nil }
        return { () throws(SessionWakeFailure) in _ = try SessionWake.wake() }
    }

    private static func meansNoSessionProcess(_ error: SessionConnectionError) -> Bool {
        switch error {
        case .noSessionProcess, .protocolFailure(.connectionClosed): true
        case .protocolFailure(.systemCallFailed(_, let code)): code == ECONNRESET || code == EPIPE || code == ENOTCONN
        default: false
        }
    }

    /// Greets the session process on an open connection, such as a test's.
    init(greeting connection: MessageConnection, within limit: Duration? = nil) throws {
        self.capabilities = try SessionConnectionError.wrapping { try connection.greetSessionProcess(within: limit) }
        self.connection = connection
    }

    /// This is the one place that learns that no program listens on the
    /// socket.
    private static func connect(to location: SocketLocation) throws -> MessageConnection {
        do {
            return try MessageConnection.connect(to: location)
        } catch SessionProtocolError.systemCallFailed(let function, let code) where function == "connect" && (code == ENOENT || code == ECONNREFUSED) {
            throw SessionConnectionError.noSessionProcess(socketPath: location.path)
        } catch let error as SessionProtocolError {
            throw SessionConnectionError.protocolFailure(error)
        }
    }

    /// Sends one request and returns the answer. A failure answer becomes an
    /// error.
    public func request(_ message: ClientMessage) throws -> ServerMessage {
        let answer = try SessionConnectionError.wrapping {
            try connection.send(message)
            return try connection.receive(ServerMessage.self)
        }
        guard let answer else { throw SessionConnectionError.connectionClosed }
        if case .failure(let failure) = answer { throw SessionConnectionError.requestFailed(failure) }
        return answer
    }

    /// Every session that the session process holds.
    public func summaries() throws -> [SessionSummary] {
        guard case .sessionList(let summaries) = try request(.listSessions) else {
            throw SessionConnectionError.unexpectedAnswer(request: "list")
        }
        return summaries
    }

    /// The session that a typed identifier or identifier start means.
    public func session(matching typed: String) throws -> SessionSummary {
        try SessionIdentifierMatch.find(typed, in: summaries())
    }

    /// Gives a session a name, or removes it with `nil` or an empty name. A
    /// program in a session may name only its own session.
    public func rename(session identifier: UUID, to name: String?) throws {
        try requestAcknowledgement(.renameSession(identifier: identifier, name: name), named: "rename")
    }

    /// Raises the alert of a session with a text. A program in a session may
    /// alert only its own session.
    public func raiseAlert(session identifier: UUID, text: String) throws {
        try requestAcknowledgement(.raiseSessionAlert(identifier: identifier, text: text), named: "alert")
    }

    /// Ends the alert of a session, as when the user selects it.
    public func clearAlert(session identifier: UUID) throws {
        try requestAcknowledgement(.clearSessionAlert(identifier: identifier), named: "clear alert")
    }

    /// The projects in their order, then the projects whose folder this Mac
    /// does not know. Check `capabilities.projectsAndSettings` first.
    public func projects() throws -> [ProjectSummary] {
        guard case .projectList(let projects) = try request(.listProjects) else {
            throw SessionConnectionError.unexpectedAnswer(request: "project list")
        }
        return projects
    }

    /// Adds a project. The session process resolves `folder`: a relative
    /// path starts at `currentFolder`, and `~` is the home folder.
    public func addProject(folder: String, name: String?, currentFolder: String?) throws -> ProjectSummary {
        guard case .projectAdded(let project) = try request(.addProject(folder: folder, name: name, currentFolder: currentFolder)) else {
            throw SessionConnectionError.unexpectedAnswer(request: "project add")
        }
        return project
    }

    public func removeProject(_ identifier: UUID) throws {
        try requestAcknowledgement(.removeProject(identifier: identifier), named: "project remove")
    }

    /// Gives a project a name, or removes it with `nil` or an empty name, so
    /// that the project shows the name of its folder.
    public func renameProject(_ identifier: UUID, to name: String?) throws {
        try requestAcknowledgement(.renameProject(identifier: identifier, name: name), named: "project rename")
    }

    /// Moves a project to a place in the order, where 0 is the first.
    public func moveProject(_ identifier: UUID, to place: Int) throws {
        try requestAcknowledgement(.moveProject(identifier: identifier, place: place), named: "project move")
    }

    /// Every setting, in the order of the settings module.
    public func settings() throws -> [SettingSummary] {
        guard case .settingList(let settings) = try request(.listSettings) else {
            throw SessionConnectionError.unexpectedAnswer(request: "settings list")
        }
        return settings
    }

    /// Changes one setting. A protected setting changes only for the app.
    public func changeSetting(named name: String, to text: String) throws {
        try requestAcknowledgement(.changeSetting(name: name, text: text), named: "settings set")
    }

    /// Every agent thread, oldest first. Check `capabilities.threads` first.
    public func threads() throws -> [ThreadSummary] {
        guard case .threadList(let threads) = try request(.listThreads) else {
            throw SessionConnectionError.unexpectedAnswer(request: "thread list")
        }
        return threads
    }

    /// Makes a thread. `nil` for the model or the permission mode takes
    /// the one of the settings.
    public func createThread(agent: String, folder: String, model: String? = nil, permissionMode: String? = nil, name: String? = nil) throws -> ThreadSummary {
        let message = ClientMessage.createThread(agent: agent, folder: folder, model: model, permissionMode: permissionMode, name: name)
        guard case .threadCreated(let thread) = try request(message) else { throw SessionConnectionError.unexpectedAnswer(request: "thread new") }
        return thread
    }

    public func renameThread(_ identifier: UUID, to name: String?) throws {
        try requestAcknowledgement(.renameThread(identifier: identifier, name: name), named: "thread rename")
    }

    /// Open in Terminal: resumes the conversation of a thread with its
    /// agent in a new terminal session, and returns that session.
    public func openThreadInTerminal(_ identifier: UUID, size: SessionSize) throws -> SessionSummary {
        guard case .sessionCreated(let summary) = try request(.openThreadInTerminal(identifier: identifier, size: size)) else {
            throw SessionConnectionError.unexpectedAnswer(request: "open in terminal")
        }
        return summary
    }

    /// Ends the terminal session of a thread, so the thread takes messages again.
    public func returnThreadFromTerminal(_ identifier: UUID) throws {
        try requestAcknowledgement(.returnThreadFromTerminal(identifier: identifier), named: "return from terminal")
    }

    /// Changes the model, the permission mode, or both. The mode must be
    /// one of `permissionModes` of the summary of the thread.
    public func changeThread(_ identifier: UUID, model: String? = nil, permissionMode: String? = nil) throws {
        try requestAcknowledgement(.changeThread(identifier: identifier, model: model, permissionMode: permissionMode), named: "thread change")
    }

    public func closeThread(_ identifier: UUID) throws {
        try requestAcknowledgement(.closeThread(identifier: identifier), named: "thread close")
    }

    /// Sends a message of the user and returns its identifier.
    public func sendThreadMessage(_ identifier: UUID, text: String, images: [ThreadImage] = []) throws -> UUID {
        let message = ClientMessage.sendThreadMessage(identifier: identifier, text: text, images: images.isEmpty ? nil : images)
        guard case .threadMessageSent(let sent) = try request(message) else { throw SessionConnectionError.unexpectedAnswer(request: "thread send") }
        return sent
    }

    public func stopThread(_ identifier: UUID) throws {
        try requestAcknowledgement(.stopThread(identifier: identifier), named: "thread stop")
    }

    /// Asks the session process for the user, as the permission hook of
    /// an agent does. `request` is what the agent gave the hook. The call
    /// returns when the request ended.
    public func requestToolPermission(_ request: Data) throws -> (allows: Bool, message: String?) {
        guard case .toolPermissionAnswer(let allows, let message) = try self.request(.requestToolPermission(request: request)) else {
            throw SessionConnectionError.unexpectedAnswer(request: "permission-request")
        }
        return (allows, message)
    }

    /// Gives the answer of the user to a permission request of a thread.
    /// The session process takes it only from OpenRun.app.
    public func answerToolPermission(thread: UUID, request: String, allows: Bool, message: String? = nil) throws {
        try requestAcknowledgement(.answerToolPermission(thread: thread, request: request, allows: allows, message: message), named: "permission answer")
    }

    /// Attaches the connection to a thread. The connection then belongs
    /// to the attachment, so the client takes no more requests.
    public func attachThread(_ identifier: UUID) throws -> ThreadAttachment {
        try ThreadAttachment.attach(on: connection, to: identifier)
    }

    private func requestAcknowledgement(_ message: ClientMessage, named name: String) throws {
        guard case .acknowledged = try request(message) else { throw SessionConnectionError.unexpectedAnswer(request: name) }
    }

    /// Attaches the connection to a session, and returns once the snapshot
    /// is there. The connection then belongs to the attachment, so the
    /// client takes no more requests.
    public func attach(to identifier: UUID, size: SessionSize, relaysRawOutput: Bool, receivesSizeChanges: Bool, waitsForOutputRoom: Bool = false) throws -> SessionAttachment {
        try SessionAttachment.attach(on: connection, to: identifier, size: size, relaysRawOutput: relaysRawOutput, receivesSizeChanges: receivesSizeChanges, waitsForOutputRoom: waitsForOutputRoom)
    }
}
