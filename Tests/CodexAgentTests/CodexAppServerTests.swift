import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexAppServerTests {
    let transport = CodexMemoryTransport()

    @Test func theHandshakeAsksForTheExperimentalMethods() async throws {
        let server = CodexAppServer(transport: transport, options: CodexServerOptions(clientVersion: "1.2.3"))
        let connect = Task { try await server.connect() }
        var lines: [JSONValue] = []
        for await line in transport.written {
            lines.append(line)
            if line["method"] == .string("initialize") {
                transport.serve(#"{"id":0,"result":{"userAgent":"openrun/0.100.0","platformOs":"macos"}}"#)
            }
            if lines.count == 2 { break }
        }
        try await connect.value
        #expect(lines[0]["params"]?["capabilities"]?["experimentalApi"] == .bool(true))
        #expect(lines[0]["params"]?["clientInfo"]?["version"] == .string("1.2.3"))
        #expect(lines[1] == .object(["method": .string("initialized"), "params": .object([:])]))
        await server.shutDown()
        while await !server.hasEnded { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aServerThatRefusesTheHandshakeGivesItsError() async {
        let server = CodexAppServer(transport: transport, options: CodexServerOptions())
        let connect = Task { try await server.connect() }
        for await _ in transport.written { break }
        transport.serve(#"{"id":0,"error":{"code":-32600,"message":"Not initialized"}}"#)
        await #expect(throws: CodexRequestError.refused(code: -32600, message: "Not initialized")) { try await connect.value }
    }
}
