import AgentConversation
import Foundation
import Synchronization
@testable import CodexAgent

/// A transport in memory: the test writes the lines of the app-server and
/// reads the lines of OpenRun.
final class CodexMemoryTransport: CodexTransport {
    let output: AsyncStream<[UInt8]>
    private let server: AsyncStream<[UInt8]>.Continuation
    /// The lines that OpenRun wrote, as JSON values.
    let written: AsyncStream<JSONValue>
    private let client: AsyncStream<JSONValue>.Continuation
    private let isEnded = Mutex(false)

    init() {
        (output, server) = AsyncStream.makeStream(of: [UInt8].self)
        (written, client) = AsyncStream.makeStream(of: JSONValue.self)
    }

    /// Writes a line as the app-server.
    func serve(_ line: String) {
        server.yield(Array((line + "\n").utf8))
    }

    /// Ends the output, as when the app-server ends.
    func close() {
        isEnded.withLock { $0 = true }
        server.finish()
        client.finish()
    }

    func markOutputConsumed(_ byteCount: Int) {}

    func write(_ bytes: [UInt8]) async throws {
        guard !isEnded.withLock({ $0 }) else { throw CodexRequestError.connectionEnded }
        client.yield(try JSONValue(decoding: Data(bytes)))
    }

    func end(gracePeriod: Duration) async {
        close()
    }

    func waitForEnd() async -> ProcessEnd {
        ProcessEnd(exitStatus: 0, wasRequested: false)
    }
}
