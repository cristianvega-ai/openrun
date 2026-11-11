import AgentConversation
@testable import CodexAgent

/// An app-server on a transport in memory, after the handshake.
struct CodexServerHarness {
    let transport = CodexMemoryTransport()
    let server: CodexAppServer
    /// The lines that OpenRun writes after the handshake.
    var written: AsyncStream<JSONValue> { transport.written }

    init(options: CodexServerOptions = CodexServerOptions()) async throws {
        server = CodexAppServer(transport: transport, options: options)
        let connect = Task { [server] in try await server.connect() }
        var count = 0
        for await line in transport.written {
            count += 1
            if line["method"] == .string("initialize") { transport.serve(#"{"id":0,"result":{}}"#) }
            if count == 2 { break }
        }
        try await connect.value
    }

    /// The next line that OpenRun writes.
    func nextWritten() async -> JSONValue? {
        for await line in transport.written { return line }
        return nil
    }

    func serve(_ line: String) {
        transport.serve(line)
    }
}
