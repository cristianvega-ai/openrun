import AgentConversation

/// The JSON-RPC connection to one app-server: the requests of OpenRun
/// with their answers, and the lines that the app-server starts.
///
/// One task reads the output. It gives each answer to its request, and
/// each other line to the receiver, one at a time and in order. A request
/// fails when its time limit passes, and every request that waits fails
/// when the output ends.
actor CodexConnection {
    typealias Receiver = @Sendable (CodexMessageReader.Incoming) async -> Void

    struct Waiting {
        var method: String
        var continuation: CheckedContinuation<JSONValue, any Error>
        var timer: Task<Void, Never>
    }

    let transport: any CodexTransport
    let lineByteLimit: Int
    private var nextIdentifier = 0
    private var waiting: [Int: Waiting] = [:]
    private(set) var hasEnded = false
    private let lines: AsyncStream<[UInt8]>.Continuation

    init(transport: any CodexTransport, lineByteLimit: Int = CodexMessageReader.defaultLineByteLimit) {
        self.transport = transport
        self.lineByteLimit = lineByteLimit
        // One writer task keeps the lines in the order of their send.
        let (stream, continuation) = AsyncStream.makeStream(of: [UInt8].self)
        lines = continuation
        Task { [transport] in
            for await line in stream {
                do { try await transport.write(line) } catch { break }
            }
        }
    }

    // Without an owner, the writer ends, and so the program can end too.
    deinit { lines.finish() }

    /// Starts to read. `ended` runs once, after the last line, with the
    /// end of the app-server.
    ///
    /// The task holds the connection and the program weakly. A program that
    /// nobody holds ends its process group, and its output then ends.
    func start(receiver: @escaping Receiver, ended: @escaping @Sendable (ProcessEnd) async -> Void) {
        Task { [weak self, weak transport, output = transport.output, lineByteLimit] in
            var reader = CodexMessageReader(lineByteLimit: lineByteLimit)
            for await bytes in output {
                guard let self else { return }
                for incoming in reader.read(bytes) where !(await self.resolve(incoming)) { await receiver(incoming) }
                transport?.markOutputConsumed(bytes.count)
            }
            guard let self else { return }
            for incoming in reader.finish() where !(await self.resolve(incoming)) { await receiver(incoming) }
            await self.endAll()
            await ended(await self.transport.waitForEnd())
        }
    }

    /// Sends a request and waits for its answer.
    func request(_ method: String, _ parameters: JSONValue, timeLimit: Duration) async throws -> JSONValue {
        guard !hasEnded else { throw CodexRequestError.connectionEnded }
        let identifier = nextIdentifier
        nextIdentifier += 1
        let line = try CodexOutgoingLine.request(.number(identifier), method: method, parameters: parameters)
        return try await withCheckedThrowingContinuation { continuation in
            let timer = Task { [weak self] in
                guard (try? await Task.sleep(for: timeLimit)) != nil else { return }
                await self?.finish(identifier, with: .failure(CodexRequestError.timedOut(method: method)))
            }
            waiting[identifier] = Waiting(method: method, continuation: continuation, timer: timer)
            lines.yield(line)
        }
    }

    /// Sends a notification, or the answer or refusal of a request of the
    /// app-server. A line after the end goes nowhere.
    func send(_ line: [UInt8]) {
        guard !hasEnded else { return }
        lines.yield(line)
    }

    /// Gives an answer to its request. Returns false for any other line.
    private func resolve(_ incoming: CodexMessageReader.Incoming) -> Bool {
        switch incoming {
        case .message(.response(.number(let identifier), let result), _) where waiting[identifier] != nil:
            finish(identifier, with: .success(result))
        case .message(.failure(.number(let identifier)?, let code, let message), _) where waiting[identifier] != nil:
            finish(identifier, with: .failure(CodexRequestError.refused(code: code, message: message)))
        default:
            return false
        }
        return true
    }

    private func finish(_ identifier: Int, with result: Result<JSONValue, any Error>) {
        guard let request = waiting.removeValue(forKey: identifier) else { return }
        request.timer.cancel()
        request.continuation.resume(with: result)
    }

    /// Fails every request that waits, and every later one.
    private func endAll() {
        hasEnded = true
        lines.finish()
        for identifier in waiting.keys { finish(identifier, with: .failure(CodexRequestError.connectionEnded)) }
    }
}
