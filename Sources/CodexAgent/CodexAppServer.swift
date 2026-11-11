import AgentConversation
import AgentProgram

/// One `codex app-server` for one account, and its open threads.
///
/// Many threads share the app-server. Each notification goes to the thread
/// that it names. A notification without a thread, such as the usage of
/// the account, goes to every open thread.
public actor CodexAppServer {
    let connection: CodexConnection
    let options: CodexServerOptions
    var isShuttingDown = false
    /// Whether the app-server ended. A new thread then needs a new server.
    public private(set) var hasEnded = false

    /// Starts `codex app-server` and makes the handshake.
    public static func start(_ launch: CodexServerLaunch, options: CodexServerOptions = CodexServerOptions()) async throws -> CodexAppServer {
        let server = CodexAppServer(transport: try AgentProgram(launching: launch.programLaunch), options: options)
        do {
            try await server.connect()
        } catch {
            await server.shutDown()
            throw error
        }
        return server
    }

    init(transport: any CodexTransport, options: CodexServerOptions) {
        connection = CodexConnection(transport: transport, lineByteLimit: options.lineByteLimit)
        self.options = options
    }

    /// Starts to read, then sends `initialize` with the experimental
    /// capability that the stop needs, and `initialized`.
    func connect() async throws {
        await connection.start(receiver: { incoming in await self.receive(incoming) }, ended: { end in await self.ended(end) })
        let client = JSONValue.object([
            "name": .string(options.clientName), "title": .string("OpenRun"), "version": .string(options.clientVersion),
        ])
        let parameters = JSONValue.object(["clientInfo": client, "capabilities": .object(["experimentalApi": .bool(true)])])
        _ = try await request("initialize", parameters)
        await connection.send(try CodexOutgoingLine.notification(method: "initialized", parameters: .object([:])))
    }

    func request(_ method: String, _ parameters: JSONValue) async throws -> JSONValue {
        try await connection.request(method, parameters, timeLimit: options.answerTimeLimit)
    }

    /// Ends the app-server: its input closes, and after a grace period it
    /// gets a signal.
    public func shutDown() async {
        isShuttingDown = true
        await connection.transport.end(gracePeriod: .seconds(2))
    }

    func ended(_ end: ProcessEnd) async {
        hasEnded = true
    }

    func receive(_ incoming: CodexMessageReader.Incoming) async {}
}
