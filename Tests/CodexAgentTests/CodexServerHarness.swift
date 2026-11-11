import AgentConversation
import Foundation
import Testing
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

    /// Plays the part of the app-server in a recorded exchange: it checks
    /// each line of OpenRun against the step, and writes the lines of the
    /// server. Returns the lines of OpenRun.
    @discardableResult
    func play(_ name: String) async throws -> [JSONValue] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var request: JSONValue = .null
        var lines: [JSONValue] = []
        for step in try CodexFixture(name: name).steps {
            if let method = step["client"]?.string {
                guard let line = await nextWritten() else { throw CodexRequestError.connectionEnded }
                lines.append(line)
                let content = method == "answer" ? line["result"] : line["params"]
                #expect(method == "answer" ? line["method"] == nil : line["method"] == .string(method), "\(line)")
                for (key, value) in step["expect"]?.object ?? [:] { #expect(content?[key] == value, "\(key) of \(method)") }
                if method != "answer" { request = line["id"] ?? .null }
            } else if case .object(var line)? = step["server"] {
                if line["id"] == .string("$request") { line["id"] = request }
                serve(String(decoding: try encoder.encode(JSONValue.object(line)), as: UTF8.self))
            }
        }
        return lines
    }
}
