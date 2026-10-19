import Foundation
import SessionProtocol
import TerminalEmulation

/// Accepts clients and answers their requests.
actor SessionServer {
    private let listener: SocketListener
    private var handlers: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var clients: [ObjectIdentifier: ClientConnection] = [:]
    private var acceptTask: Task<Void, Never>?

    /// Starts listening. Throws when another session process already does.
    init(location: SocketLocation) throws {
        listener = try SocketListener(location: location)
    }

    func start() {
        let connections = listener.connections
        acceptTask = Task {
            for await connection in connections {
                self.accept(connection)
            }
        }
    }

    func shutDown() async {
        listener.close()
        await acceptTask?.value
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

        messages: for await received in client.messages {
            switch received.message {
            case .hello:
                client.send(.failure(SessionFailure(reason: .invalidRequest, message: "Hello was already sent.")))
            case .detach:
                break messages
            default:
                client.send(.failure(SessionFailure(reason: .invalidRequest, message: "The session process does not handle this request yet.")))
            }
        }

        client.closeAfterSending()
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
