import Foundation
import SessionProcessHarness

/// A real session process whose threads run the fake agent in place of
/// Claude Code, with the environment of the test.
enum FakeAgentProcess {
    static let fixtures = RunningSessionProcess.fakeAgentFixtures

    /// - Parameters:
    ///   - turns: The recorded turns that the agent plays, in order.
    ///   - isApplication: Whether this test process counts as OpenRun.app,
    ///     which alone answers a permission request.
    static func start(
        turns: [String] = ["plain-turn"], mode: String = "replay", isApplication: Bool = false, environment: [String: String] = [:]
    ) throws -> RunningSessionProcess {
        let arguments = isApplication ? ["--answerer-requirement", "cdhash H\"\(try codeHashOfThisProcess())\""] : []
        let request = ["FAKE_AGENT_PERMISSION_REQUEST": fixtures.appending(path: "permission-request.json").path]
        return try RunningSessionProcess.withFakeAgent(turns: turns, mode: mode, arguments: arguments, environment: request.merging(environment) { $1 })
    }
}
