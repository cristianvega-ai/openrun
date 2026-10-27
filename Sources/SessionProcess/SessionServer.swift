import Foundation
import SessionProtocol
import TerminalEmulation

/// Accepts clients and answers their requests.
actor SessionServer {
    private let listener: SocketListener
    private let registry: SessionRegistry
    private var handlers: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var clients: [ObjectIdentifier: ClientConnection] = [:]
    private var acceptTask: Task<Void, Never>?
    /// The last moment with a client or a session, for the idle exit.
    private var lastBusy = ContinuousClock.now
    private var isClosed = false

    /// Starts listening. Throws when another session process already does.
    init(location: SocketLocation) throws {
        listener = try SocketListener(location: location)
        // The path of the program is read at the start, because a new build
        // can replace the bundle while the process runs.
        registry = SessionRegistry(socketPath: location.path, helperSearchPath: .ofThisProcess())
    }

    func start() {
        let connections = listener.connections
        acceptTask = Task {
            for await connection in connections {
                self.accept(connection)
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

    private func accept(_ connection: MessageConnection) {
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
            await self.serve(client)
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
    private func serve(_ client: ClientConnection) async {
        let owner = ObjectIdentifier(client)
        var attachedSession: Session?

        messages: for await received in client.messages {
            if Task.isCancelled { break }
            switch received.message {
            case .hello:
                client.send(.failure(SessionFailure(reason: .invalidRequest, message: "Hello was already sent.")))
            case .createSession(let folder, let command, let size, let environment):
                client.send(await create(folder: folder, command: command, size: size, environment: environment))
            case .listSessions:
                client.send(.sessionList(await registry.summaries()))
            case .readScreen(let identifier, let includeScrollback):
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
            case .attach(let identifier, let size, let relaysRawOutput, let receivesSizeChanges):
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
                do {
                    let attachment = try await session.attach(
                        client, size: size, relaysRawOutput: relaysRawOutput ?? false, receivesSizeChanges: receivesSizeChanges ?? false
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
                // The bytes go in behind this client's earlier input, and leave
                // the read-ahead once they are in the backlog. The loop does not
                // wait for them, so the client can still detach while its
                // program reads nothing.
                session.type(Array(bytes), from: owner) { client.markHandled(received) }
                continue
            case .resize(let size):
                try? await attachedSession?.resize(to: size, from: client)
            case .detach:
                client.markHandled(received)
                break messages
            }
            client.markHandled(received)
        }

        if let attachedSession {
            await attachedSession.detach(client)
            attachedSession.withdrawTypedInput(from: owner)
        }
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

    private static func unknownSession(_ identifier: UUID) -> ServerMessage {
        .failure(SessionFailure(reason: .unknownSession, message: "No session has the identifier \(SessionSummary.text(for: identifier))."))
    }

    /// Logs a message that can hold a path or an error text, so all of it
    /// is private in the unified log. See `SessionLog`.
    static func log(_ message: String) {
        SessionLog.write("", detail: message)
    }
}
