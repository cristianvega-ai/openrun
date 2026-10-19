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

    /// Starts listening. Throws when another session process already does.
    init(location: SocketLocation) throws {
        listener = try SocketListener(location: location)
        registry = SessionRegistry(socketPath: location.path)
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
        listener.close()
        await acceptTask?.value
        await registry.terminateAll()
        for client in clients.values { client.closeAfterSending() }
        for handler in handlers.values { await handler.value }
    }

    // MARK: - Clients

    private func accept(_ connection: MessageConnection) {
        let client = ClientConnection(connection: connection)
        let key = ObjectIdentifier(client)
        clients[key] = client
        let handler = Task {
            await self.serve(client)
            self.finish(key)
        }
        handlers[key] = handler
    }

    private func finish(_ key: ObjectIdentifier) {
        clients[key] = nil
        handlers[key] = nil
    }

    private func serve(_ client: ClientConnection) async {
        var attachedSession: Session?

        messages: for await received in client.messages {
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
                await session.terminate()
                client.send(.acknowledged)
            case .attach(let identifier, let size, let relaysRawOutput, let receivesSizeChanges):
                guard attachedSession == nil else {
                    client.send(.failure(SessionFailure(reason: .invalidRequest, message: "This connection is already attached.")))
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
            case .detach:
                break messages
            default:
                client.send(.failure(SessionFailure(reason: .invalidRequest, message: "The session process does not handle this request yet.")))
            }
        }

        if let attachedSession {
            await attachedSession.detach(client)
        }
        client.closeAfterSending()
    }

    private func create(folder: String, command: [String]?, size: SessionSize, environment: [String: String]) async -> ServerMessage {
        do {
            let summary = try await registry.create(folder: folder, command: command, size: size, environment: environment)
            Self.log("Started session \(summary.identifierText) in \(folder)")
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

    /// The session process runs in the foreground and logs to standard error.
    /// A message can include text that a client chose, such as a folder, a
    /// command or an error message, and a terminal that shows the log must not
    /// obey it. Every log line passes here, so one escape covers them all, and
    /// a value with a line break cannot forge a second line.
    static func log(_ message: String) {
        FileHandle.standardError.write(Data("openrun-session: \(PrintableText.escaping(message))\n".utf8))
    }
}
