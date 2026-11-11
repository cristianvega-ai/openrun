import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexConnectionTests {
    let transport = CodexMemoryTransport()

    func connection() async -> CodexConnection {
        let connection = CodexConnection(transport: transport)
        await connection.start(receiver: { _ in }, ended: { _ in })
        return connection
    }

    @Test func eachAnswerGoesToItsRequest() async throws {
        let connection = await connection()
        let first = Task { try await connection.request("a", .object([:])) }
        let second = Task { try await connection.request("b", .object([:])) }
        var methods: [String: Int] = [:]
        for await line in transport.written {
            methods[line["method"]?.string ?? ""] = line["id"]?.integer
            if methods.count == 2 { break }
        }
        transport.serve(#"{"id":\#(methods["b"]!),"result":"for b"}"#)
        transport.serve(#"{"id":\#(methods["a"]!),"error":{"code":-32600,"message":"no"}}"#)
        #expect(try await second.value == .string("for b"))
        await #expect(throws: CodexRequestError.refused(code: -32600, message: "no")) { try await first.value }
    }

    @Test func theEndOfTheOutputFailsEveryRequest() async {
        let connection = await connection()
        let waiting = Task { try await connection.request("a", .object([:])) }
        for await _ in transport.written { break }
        transport.close()
        await #expect(throws: CodexRequestError.connectionEnded) { try await waiting.value }
        await #expect(throws: CodexRequestError.connectionEnded) {
            try await connection.request("b", .object([:]))
        }
    }
}
