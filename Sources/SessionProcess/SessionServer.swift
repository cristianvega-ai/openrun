import Foundation
import SessionProtocol
import TerminalEmulation

/// Accepts clients and answers their requests.
actor SessionServer {
    private let listener: SocketListener
    private let registry: SessionRegistry
    private let questions = ApprovalQuestions()
    private let changes = SessionChangeFeed()
    private let answererRequirement: AnswererRequirement
    private var handlers: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var clients: [ObjectIdentifier: ClientConnection] = [:]
    private var acceptTask: Task<Void, Never>?
    /// The last moment with a client or a session, for the idle exit.
    private var lastBusy = ContinuousClock.now
    private var isClosed = false

    /// Starts listening. Throws when another session process already does.
    init(location: SocketLocation, answererRequirement: AnswererRequirement = AnswererRequirement(text: nil)) throws {
        self.answererRequirement = answererRequirement
        listener = try SocketListener(location: location)
        // The path of the program is read at the start, because a new build
        // can replace the bundle while the process runs.
        registry = SessionRegistry(socketPath: location.path, helperSearchPath: .ofThisProcess(), changes: changes)
    }

    func start() {
        let connections = listener.connections
        acceptTask = Task {
            for await accepted in connections {
                self.accept(accepted.connection, peer: accepted.peer)
            }
        }
    }

    /// Stops accepting, ends every program, and closes every client. The
    /// socket file goes first, so no client can connect to a process that is
    /// about to leave.
    func shutDown() async {
        close()
        await acceptTask?.value
        await registry.terminateAll()
        // Each client gets a short time to take what still waits for it, such
        // as the exit status of its program. See `closeAfterSending`.
        for client in clients.values { client.closeAfterSending() }
        for handler in handlers.values { await handler.value }
    }

    /// Closes the socket when no client and no session was there for
    /// `limit`, and returns whether it did. `beforeClosing` runs first.
    func closeWhenIdle(for limit: Duration, beforeClosing: @Sendable () -> Void) async -> Bool {
        // Clients can arrive while the registry answers, so they are checked
        // again after it. No wait comes between that check and the close.
        guard !isClosed, clients.isEmpty, await registry.isEmpty, clients.isEmpty else {
            lastBusy = .now
            return false
        }
        guard ContinuousClock.now - lastBusy >= limit else { return false }
        beforeClosing()
        close()
        return true
    }

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        listener.close()
    }

    // MARK: - Clients

    private func accept(_ connection: MessageConnection, peer: PeerProcess) {
        // The listener can take a connection just before the socket closes.
        // It closes before hello, so its client wakes the next process.
        guard !isClosed else {
            connection.shutdown()
            return
        }
        guard clients.count < ConnectionLimits.maximumClientCount else {
            // The client reads this in place of hello. The reason is an
            // existing one, so protocol version 1 does not change.
            try? connection.send(ServerMessage.failure(SessionFailure(
                reason: .invalidRequest,
                message: "The session process already serves \(ConnectionLimits.maximumClientCount) clients, its limit. Close a client and try again."
            )), stallLimit: .zero)
            connection.shutdown()
            return
        }
        let client = ClientConnection(connection: connection)
        let key = ObjectIdentifier(client)
        clients[key] = client
        let handler = Task {
            await self.serve(client, peer: peer)
            // The place stays taken until the socket is closed and both of the
            // client's threads are done with it. A client that detaches while
            // its last messages still go out counts until then, so clients
            // that come and go fast cannot hold more than the limit of sockets.
            await client.waitUntilClosed()
            self.finish(key)
        }
        handlers[key] = handler
        // A client that leaves is served no further, also while its handler
        // waits, for example for room for its text.
        client.whenClientLeaves { handler.cancel() }
    }

    private func finish(_ key: ObjectIdentifier) {
        clients[key] = nil
        handlers[key] = nil
        lastBusy = .now
    }

    /// Reads messages from one client until it leaves. A connection does one
    /// request after another, and an attach lasts until the client detaches.
    ///
    /// Each message counts against the client's read-ahead until it is handled.
    /// Typed input is handled once it is in the program's backlog.
    ///
    /// When the client detaches or leaves, its input that has not gone to the
    /// program yet is dropped, and its requests that were not handled yet are
    /// dropped too. A client that leaves therefore holds no memory.
    private func serve(_ client: ClientConnection, peer: PeerProcess) async {
        let owner = ObjectIdentifier(client)
        var attachedSession: Session?
        var isWatching = false

        messages: for await received in client.messages {
            if Task.isCancelled { break }
            // An answer would mix with the changes, so a watcher only leaves.
            if isWatching, received.message != .detach {
                client.send(.failure(SessionFailure(reason: .invalidRequest, message: "This connection receives the session changes and takes no other request.")))
                client.markHandled(received)
                continue
            }
            switch received.message {
            case .hello:
                client.send(.failure(SessionFailure(reason: .invalidRequest, message: "Hello was already sent.")))
            case .createSession(let folder, let command, let size, let environment):
                client.send(await create(folder: folder, command: command, size: size, environment: environment))
            case .listSessions:
                client.send(.sessionList(await registry.summaries()))
            case .readScreen(let identifier, let includeScrollback):
                if let refusal = await refusal(of: peer, toward: identifier, .read) {
                    client.send(refusal)
                    break
                }
                let answer = await readScreen(identifier, includeScrollback: includeScrollback)
                if case .screen = answer {
                    // A screen can be larger than the output limit, so it does
                    // not count. The next request waits until it is written,
                    // so a client that asks without reading cannot pile them up.
                    await client.sendAndWait(answer)
                } else {
                    client.send(answer)
                }
            case .sendText(let identifier, let text):
                guard let session = await registry.session(for: identifier) else {
                    client.send(Self.unknownSession(identifier))
                    break
                }
                if let refusal = await refusal(of: peer, toward: identifier, .typing(text)) {
                    client.send(refusal)
                    break
                }
                await session.noteInput(isTyped: false)
                // The answer waits until the text is in the program's backlog,
                // so a client never hears that text arrived when it was lost.
                // The text goes in behind the input that this client typed.
                do {
                    try await session.type(Array(text.utf8))
                    client.send(.acknowledged)
                } catch is CancellationError {
                    break messages
                } catch {
                    client.send(.failure(SessionFailure(
                        reason: .unknownSession,
                        message: "The program of session \(SessionSummary.text(for: identifier)) ended before it took the text."
                    )))
                }
            case .killSession(let identifier):
                guard let session = await registry.session(for: identifier) else {
                    client.send(Self.unknownSession(identifier))
                    break
                }
                if let refusal = await refusal(of: peer, toward: identifier, .kill) {
                    client.send(refusal)
                    break
                }
                guard session === attachedSession else {
                    await session.terminate()
                    client.send(.acknowledged)
                    break
                }
                // The end of the session would close this connection before
                // the answer. So the client leaves the session first, and gets
                // the answer and then the exit status from here.
                await session.detach(client)
                session.withdrawTypedInput(from: owner)
                attachedSession = nil
                let exit = await session.terminate()
                client.send(.acknowledged)
                client.send(.exited(exit), countsTowardOutputLimit: false)
                client.markHandled(received)
                break messages
            case .attach(let identifier, let size, let relaysRawOutput, let receivesSizeChanges, let waitsForOutputRoom):
                guard attachedSession == nil else {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "This connection is already attached.")))
                    break
                }
                guard size.columns > 0, size.rows > 0 else {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "A session needs at least one column and one row.")))
                    break
                }
                guard let session = await registry.session(for: identifier) else {
                    client.send(Self.unknownSession(identifier))
                    break
                }
                if let refusal = await refusal(of: peer, toward: identifier, .attach) {
                    client.send(refusal)
                    break
                }
                do {
                    let attachment = try await session.attach(
                        client, size: size, relaysRawOutput: relaysRawOutput ?? false,
                        receivesSizeChanges: receivesSizeChanges ?? false, waitsForOutputRoom: waitsForOutputRoom ?? false
                    )
                    switch attachment {
                    case .attached: attachedSession = session
                    case .sessionEnded: client.send(Self.unknownSession(identifier))
                    case .refused(let failure): client.send(.failure(failure))
                    }
                } catch {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "\(error)")))
                }
            case .input(let bytes):
                guard let session = attachedSession else { break }
                await session.noteInput(isTyped: true)
                // The bytes go in behind this client's earlier input, and leave
                // the read-ahead once they are in the backlog. The loop does not
                // wait for them, so the client can still detach while its
                // program reads nothing.
                session.type(Array(bytes), from: owner) { client.markHandled(received) }
                continue
            case .resize(let size, let confirmation):
                if confirmation == true && (attachedSession == nil || size.columns == 0 || size.rows == 0) {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "A resize needs an attached session and a nonzero size.")))
                    client.markHandled(received)
                    break messages
                }
                do {
                    try await attachedSession?.resize(to: size, from: client, confirmsResize: confirmation == true)
                } catch {
                    if confirmation == true {
                        client.send(.failure(SessionFailure(reason: .invalidRequest, message: "The session could not change size: \(error)")))
                        client.markHandled(received)
                        break messages
                    }
                }
            case .detach:
                client.markHandled(received)
                break messages
            case .receiveApprovalQuestions:
                // The app, signed and outside every session, is the only
                // program that can answer (ApprovalQuestion.tla).
                guard Self.acceptsAnswerer(at: await registry.place(of: peer), meetingRequirement: answererRequirement.isMet(byProgramWithAuditToken: peer.auditToken)) else {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "Only OpenRun.app receives approval questions.")))
                    break
                }
                client.send(.acknowledged)
                await questions.addAnswerer(owner) { client.send($0) }
            case .answerApprovalQuestion(let identifier, let allows):
                await questions.answer(identifier, allows: allows, from: owner)
            case .receiveSessionChanges:
                guard attachedSession == nil else {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "This connection is attached.")))
                    break
                }
                isWatching = true
                changes.addWatcher(owner) { client.send($0) }
            case .renameSession, .raiseSessionAlert, .clearSessionAlert:
                // The capability `sessionChanges` is off until these work.
                client.send(.failure(SessionFailure(reason: .invalidRequest, message: "This session process does not keep the facts of its sessions.")))
            }
            client.markHandled(received)
        }

        if let attachedSession {
            await attachedSession.detach(client)
            attachedSession.withdrawTypedInput(from: owner)
        }
        await questions.removeAnswerer(owner)
        changes.removeWatcher(owner)
        client.closeAfterSending()
    }

    private func create(folder: String, command: [String]?, size: SessionSize, environment: [String: String]) async -> ServerMessage {
        guard size.columns > 0, size.rows > 0 else {
            return .failure(SessionFailure(reason: .invalidRequest, message: "A session needs at least one column and one row."))
        }
        // No command means the login shell. An empty one names no program, so
        // it is a mistake of the client, not a request for the shell.
        if let command, command.isEmpty {
            return .failure(SessionFailure(reason: .invalidRequest, message: "The command is empty. Name a program, or send no command to start the login shell."))
        }
        do {
            let summary = try await registry.create(folder: folder, command: command, size: size, environment: environment)
            SessionLog.write("Started session \(summary.identifierText) in ", detail: folder)
            return .sessionCreated(summary)
        } catch {
            return .failure(SessionFailure(reason: .launchFailed, message: "\(error)"))
        }
    }

    private func readScreen(_ identifier: UUID, includeScrollback: Bool) async -> ServerMessage {
        guard let session = await registry.session(for: identifier) else { return Self.unknownSession(identifier) }
        do {
            return .screen(text: try await session.screenText(includeScrollback: includeScrollback))
        } catch {
            return .failure(SessionFailure(reason: .invalidRequest, message: "\(error)"))
        }
    }

    /// What a caller in one session wants to do to another one.
    /// Nil when the caller may do a request on the target session: the
    /// caller may act on it freely, or the user allowed it. Otherwise the
    /// refusal. While the question waits, this client sends no other request
    /// (decisions of 2026-10-15 and 2026-11-10, ApprovalQuestion.tla).
    private func refusal(of peer: PeerProcess, toward target: UUID, _ request: ApprovalQuestion.Request) async -> ServerMessage? {
        let place = await registry.place(of: peer)
        guard !place.mayAct(on: target) else { return nil }
        let verb = switch request {
        case .type: "type into"
        case .read: "read"
        case .attach: "attach to"
        case .kill: "kill"
        }
        let targetText = SessionSummary.text(for: target)
        guard case .session(let own) = place, let asking = await registry.session(for: own),
              let targetSession = await registry.session(for: target) else {
            return Self.refusal("The program that asked to \(verb) session \(targetText) runs in no session that the session process can name, such as one that has ended. Such a request needs the user's approval, and it is refused.")
        }
        let start = "A program in session \(SessionSummary.text(for: own)) asked to \(verb) session \(targetText)"
        let question = ApprovalQuestion(identifier: UUID(), askingSession: await asking.summary, targetSession: await targetSession.summary, request: request)
        switch await questions.ask(question) {
        case .allowed: return nil
        case .denied: return Self.refusal("\(start), and the user did not allow it.")
        case .timedOut: return Self.refusal("\(start), and the user did not answer in time.")
        case .noAnswerer: return Self.refusal("\(start). This needs the user's approval, and no signed OpenRun app is open to ask.")
        case .withdrawn: return Self.refusal("\(start), and then it left.")
        case .anotherQuestionWaits: return Self.refusal("\(start) while another question of that session waits for the user.")
        }
    }

    /// Only the signed app outside every session receives questions. An app
    /// that a program in a session started counts as that program.
    static func acceptsAnswerer(at place: CallerPlace, meetingRequirement: Bool) -> Bool {
        place == .outsideEverySession && meetingRequirement
    }

    /// The reason is an existing one, so protocol version 1 does not change.
    private static func refusal(_ message: String) -> ServerMessage {
        .failure(SessionFailure(reason: .invalidRequest, message: message))
    }

    private static func unknownSession(_ identifier: UUID) -> ServerMessage {
        .failure(SessionFailure(reason: .unknownSession, message: "No session has the identifier \(SessionSummary.text(for: identifier))."))
    }

    /// Logs a message that can hold a path or an error text, so all of it
    /// is private in the unified log. See `SessionLog`.
    static func log(_ message: String) {
        SessionLog.write("", detail: message)
    }
}
