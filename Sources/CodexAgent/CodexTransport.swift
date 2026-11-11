import AgentConversation
import AgentProgram
import PseudoTerminal

/// The pipes to an app-server and its end. The real one is an
/// `AgentProgram`. Tests can give one that holds the lines in memory.
protocol CodexTransport: AnyObject, Sendable {
    /// The bytes of standard output, in order. Only one task reads it.
    var output: AsyncStream<[UInt8]> { get }
    /// Tells the transport that the reader dealt with this many bytes.
    func markOutputConsumed(_ byteCount: Int)
    /// Sends bytes after every earlier write, or throws when the
    /// app-server cannot take them.
    func write(_ bytes: [UInt8]) async throws
    /// Closes the input of the app-server. It then ends by itself, and
    /// after `gracePeriod` it is made to end.
    func end(gracePeriod: Duration) async
    /// Waits for the end of the app-server and tells how it ended.
    func waitForEnd() async -> ProcessEnd
}

extension AgentProgram: CodexTransport {
    func end(gracePeriod: Duration) async {
        closeInput()
        // The first of the end and the grace period finishes the stream.
        // A wait for the end cannot be cancelled, so it is not a child task.
        let (first, continuation) = AsyncStream.makeStream(of: Void.self)
        Task { _ = await self.waitForExit(); continuation.finish() }
        Task { try? await Task.sleep(for: gracePeriod); continuation.finish() }
        for await _ in first {}
        // After the end, this does nothing and returns at once.
        await terminate()
    }

    func waitForEnd() async -> ProcessEnd {
        switch await waitForExit() {
        case .exited(let status): ProcessEnd(exitStatus: status, wasRequested: false, standardErrorText: standardErrorText)
        case .signaled(let signal): ProcessEnd(exitStatus: nil, signal: signal, wasRequested: false, standardErrorText: standardErrorText)
        }
    }
}
