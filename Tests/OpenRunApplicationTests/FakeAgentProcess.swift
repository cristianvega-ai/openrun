import Foundation
import SessionProcessHarness

/// A real session process whose threads run the fake agent in place of
/// Claude Code, with the environment of the test.
enum FakeAgentProcess {
    static let fixtures = URL(fileURLWithPath: "../ClaudeCodeAgentTests/Fixtures", relativeTo: URL(fileURLWithPath: #filePath)).standardizedFileURL

    /// - Parameters:
    ///   - turns: The recorded turns that the agent plays, in order.
    ///   - isApplication: Whether this test process counts as OpenRun.app,
    ///     which alone answers a permission request.
    static func start(turns: [String] = ["plain-turn"], mode: String = "replay", isApplication: Bool = false) throws -> RunningSessionProcess {
        let agent = RunningSessionProcess.productsDirectory.appendingPathComponent("fake-agent").path
        var arguments = ["--agent-program", agent, "--own-environment-for-agents"]
        if isApplication { arguments += ["--answerer-requirement", "cdhash H\"\(try codeHashOfThisProcess())\""] }
        let environment = [
            "FAKE_AGENT_TURNS": turns.map { fixtures.appending(path: $0 + ".jsonl").path }.joined(separator: ":"), "FAKE_AGENT_MODE": mode,
            "FAKE_AGENT_PERMISSION_REQUEST": fixtures.appending(path: "permission-request.json").path,
        ]
        return try RunningSessionProcess(arguments: arguments, environment: environment)
    }
}
