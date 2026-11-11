import AgentConversation
import Synchronization
import Testing
@testable import CodexAgent

@Suite struct CodexConnectionTests {
    final class Received: Sendable {
        let lines = Mutex<[CodexMessageReader.Incoming]>([])
    }

    let transport = CodexMemoryTransport()
    let received = Received()

    func connection() async -> CodexConnection {
        let connection = CodexConnection(transport: transport)
        await connection.start(receiver: { [received] incoming in received.lines.withLock { $0.append(incoming) } }, ended: { _ in })
        return connection
    }

    @Test func eachAnswerGoesToItsRequest() async throws {
        let connection = await connection()
        let first = Task { try await connection.request("a", .object([:]), timeLimit: .seconds(30)) }
        let second = Task { try await connection.request("b", .object([:]), timeLimit: .seconds(30)) }
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

    @Test func aRequestWithoutAnswerFailsAfterItsTimeLimit() async {
        let connection = await connection()
        await #expect(throws: CodexRequestError.timedOut(method: "thread/start")) {
            try await connection.request("thread/start", .object([:]), timeLimit: .milliseconds(50))
        }
    }

    @Test func theEndOfTheOutputFailsEveryRequest() async {
        let connection = await connection()
        let waiting = Task { try await connection.request("a", .object([:]), timeLimit: .seconds(30)) }
        for await _ in transport.written { break }
        transport.close()
        await #expect(throws: CodexRequestError.connectionEnded) { try await waiting.value }
        await #expect(throws: CodexRequestError.connectionEnded) {
            try await connection.request("b", .object([:]), timeLimit: .seconds(30))
        }
    }

    @Test func otherLinesReachTheReceiverInOrder() async throws {
        let connection = await connection()
        transport.serve(#"{"method":"warning","params":{"message":"w"}}"#)
        transport.serve("not json")
        transport.serve(#"{"id":7,"method":"item/fileChange/requestApproval","params":{}}"#)
        transport.serve(#"{"id":99,"result":{}}"#)
        transport.close()
        while await !connection.hasEnded { try await Task.sleep(for: .milliseconds(10)) }
        let methods = received.lines.withLock { $0 }.map { incoming -> String in
            switch incoming {
            case .message(.notification(let method, _), _), .message(.request(_, let method, _), _): method
            case .message: "other"
            case .unreadable(let line, _): line.reason.rawValue
            }
        }
        #expect(methods == ["warning", "notJSON", "item/fileChange/requestApproval", "other"])
    }
}
