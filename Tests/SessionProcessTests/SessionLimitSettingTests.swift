import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

extension SessionProcessIntegration {
    /// The settings that the session process reads itself.
    @Suite struct SessionLimitSettingTests {
        /// The limit of sessions is protected, so only the program that
        /// answers the questions changes it. A change applies to the next
        /// request for a session.
        @Test func theLimitOfSessionsComesFromTheSetting() async throws {
            try await RunningSessionProcess.run(arguments: try testProcessAnswersArguments()) { process in
                #expect(try answer(to: .changeSetting(name: "session-limit", text: "2"), from: process) == .acknowledged)
                for _ in 0..<2 { _ = try process.createSession(program: ["/bin/sleep", "60"]) }
                let refused = try process.runCommand(["new", "--", "/bin/sleep", "60"])
                #expect(refused.status == 1 && refused.standardError.contains("already runs 2 sessions, its limit"), "\(refused.standardError)")
                #expect(try answer(to: .changeSetting(name: "session-limit", text: "3"), from: process) == .acknowledged)
                _ = try process.createSession(program: ["/bin/sleep", "60"])
                #expect(try process.listedIdentifiers().count == 3)
            }
        }

        /// The scrollback limit applies to the sessions that start after
        /// the change. A session that runs keeps its own. libghostty-vt
        /// removes whole pages, so a limit of 0 still keeps up to one page.
        @Test func theScrollbackLimitAppliesToNewSessions() async throws {
            try await RunningSessionProcess.run { process in
                let program = ["/bin/sh", "-c", "seq 1 5000; exec sleep 60"]
                let before = try process.createSession(program: program)
                #expect(await process.waitForScreen(of: before, containing: "5000"))
                #expect(try answer(to: .changeSetting(name: "scrollback-limit", text: "0"), from: process) == .acknowledged)
                let after = try process.createSession(program: program)
                #expect(await process.waitForScreen(of: after, containing: "5000"))
                #expect(try process.screenText(of: before, includeScrollback: true).hasPrefix("1\n2\n"))
                let kept = try process.screenText(of: after, includeScrollback: true)
                #expect(!kept.hasPrefix("1\n2\n") && kept.split(separator: "\n").count < 2000, "\(kept.prefix(100))")
            }
        }
    }
}
