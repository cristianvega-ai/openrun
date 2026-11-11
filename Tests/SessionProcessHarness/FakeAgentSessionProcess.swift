import Foundation

/// A real session process whose threads run the fake agent in place of
/// Claude Code, so that no test runs the real agent and spends the
/// subscription of the owner. A test target that uses it depends on the
/// product `fake-agent`.
extension RunningSessionProcess {
    /// The folder of the recorded turns of Claude Code.
    public static let fakeAgentFixtures = URL(fileURLWithPath: "../ClaudeCodeAgentTests/Fixtures", relativeTo: URL(fileURLWithPath: #filePath)).standardizedFileURL

    public static var fakeAgentExecutable: String { productsDirectory.appendingPathComponent("fake-agent").path }

    /// The variables that tell the fake agent what to play.
    ///
    /// - Parameter turns: The names of the recorded turns, in order. Each
    ///   message of the user plays the next one.
    public static func fakeAgentEnvironment(turns: [String] = ["plain-turn"], mode: String = "replay") -> [String: String] {
        ["FAKE_AGENT_TURNS": turns.map { fakeAgentFixtures.appending(path: $0 + ".jsonl").path }.joined(separator: ":"), "FAKE_AGENT_MODE": mode]
    }

    /// Starts a session process that gives the fake agent its own
    /// environment, and never the one of the login shell of the user.
    public static func withFakeAgent(
        turns: [String] = ["plain-turn"], mode: String = "replay", arguments: [String] = [], environment: [String: String] = [:]
    ) throws -> RunningSessionProcess {
        try RunningSessionProcess(
            arguments: ["--agent-program", fakeAgentExecutable, "--own-environment-for-agents"] + arguments,
            environment: fakeAgentEnvironment(turns: turns, mode: mode).merging(environment) { $1 })
    }
}
