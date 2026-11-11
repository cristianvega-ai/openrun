import AgentConversation
import AgentProgram
import ClaudeCodeAgent
import Foundation

/// The fake agent in place of Claude Code, run as the session process will
/// run Claude Code: through `AgentProgram`, the decoder and a transcript.
struct FakeAgentRun {
    static let fixtures = URL(fileURLWithPath: "../ClaudeCodeAgentTests/Fixtures", relativeTo: URL(fileURLWithPath: #filePath))
        .standardizedFileURL

    /// The folder of the test bundle also holds the executables that the
    /// tests depend on.
    static let executable: String = {
        if let bundle = Bundle.allBundles.first(where: { $0.bundleURL.pathExtension == "xctest" }) {
            return bundle.bundleURL.deletingLastPathComponent().appending(path: "fake-agent").path
        }
        // swift test runs the bundle from a helper process in some versions.
        let bundlePath = CommandLine.arguments.lazy.compactMap { argument in
            argument.range(of: ".xctest").map { String(argument[..<$0.upperBound]) }
        }.first
        let folder = bundlePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() } ?? Bundle.main.bundleURL.deletingLastPathComponent()
        return folder.appending(path: "fake-agent").path
    }()

    let program: AgentProgram
    var output: AsyncStream<[UInt8]>.Iterator
    var decoder = ClaudeCodeOutputDecoder()
    var transcript = Transcript()
    var events: [ConversationEvent] = []

    /// Starts the fake agent with the command line of a real thread.
    init(turns: [String], mode: String = "replay", conversation: ClaudeCodeLaunch.Conversation = .new(UUID()),
         environment extraEnvironment: [String: String] = [:]) throws {
        let launch = try ClaudeCodeLaunch(
            model: "claude-haiku-5-5", permissionMode: .standard, conversation: conversation,
            hookCommand: "/usr/bin/false", hookArguments: [])
        let paths = turns.map { Self.fixtures.appending(path: $0 + ".jsonl").path }
        let additions = ["FAKE_AGENT_TURNS": paths.joined(separator: ":"), "FAKE_AGENT_MODE": mode].merging(extraEnvironment) { $1 }
        let environment = ClaudeCodeEnvironment.make(base: ["PATH": "/usr/bin:/bin", "CLAUDECODE": "1"], additions: additions)
        program = try AgentProgram(launching: AgentProgramLaunch(
            executablePath: Self.executable, arguments: launch.arguments, folder: NSTemporaryDirectory(), environment: environment))
        output = program.output.makeAsyncIterator()
    }

    /// Sends a user message as the session process will, and returns its
    /// identifier.
    mutating func send(_ text: String) async throws -> String {
        let identifier = UUID()
        take(ConversationEvent(.userMessage(UserMessage(identifier: identifier.uuidString.lowercased(), text: text, isAccepted: false))))
        try await program.write(try ClaudeCodeUserMessage.line(identifier: identifier, text: text))
        return identifier.uuidString.lowercased()
    }

    /// Reads until an event that `isWanted` accepts, or until the output
    /// ends. Returns that event.
    mutating func read(until isWanted: (ConversationEventKind) -> Bool) async -> ConversationEventKind? {
        while let chunk = await output.next() {
            program.markOutputConsumed(chunk.count)
            let decoded = decoder.decode(chunk)
            decoded.forEach { take($0) }
            if let wanted = decoded.first(where: { isWanted($0.kind) }) { return wanted.kind }
        }
        decoder.finish().forEach { take($0) }
        return nil
    }

    /// Reads until a turn ends, and returns its end.
    mutating func readTurn() async -> TurnEnd? {
        guard case .turnEnded(let end)? = await read(until: { if case .turnEnded = $0 { true } else { false } }) else { return nil }
        return end
    }

    mutating func take(_ event: ConversationEvent) {
        events.append(event)
        _ = transcript.apply(event)
    }
}
