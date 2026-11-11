import Foundation
import SessionProcessHarness
import Testing

extension SessionProcessIntegration {
    /// A program in a session may name or alert only its own session, and
    /// another session refuses at once, with no question (decision of
    /// 2026-11-10).
    @Suite struct SessionFactCallerTests {
        @Test func aProgramRenamesItsOwnSessionAndNoOther() async throws {
            try await RunningSessionProcess.run { process in
                let target = try process.createSession(program: ["/bin/sh", "-c", "exec sleep 60"])
                let script = [
                    "\(openrun(process, "rename \"$OPENRUN_SESSION\" Release build")); echo own=$?",
                    "\(openrun(process, "rename \(target) taken")) 2>&1; echo other=$?",
                    "exec sleep 60",
                ].joined(separator: "; ")
                let caller = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: caller, containing: "other="))
                let screen = try process.screenText(of: caller)
                #expect(screen.contains("own=0") && screen.contains("other=1"), "\(screen)")
                #expect(screen.contains("Only a program outside every session"), "\(screen)")
                let names = Dictionary(uniqueKeysWithValues: try listedSummaries(of: process).map { ($0.identifierText, $0.name) })
                #expect(names[caller] == "Release build" && names[target] == .some(nil))
            }
        }

        @Test func aProgramOutsideEverySessionRenamesAnySession() async throws {
            try await RunningSessionProcess.run { process in
                let target = try process.createSession(program: ["/bin/sh", "-c", "exec sleep 60"])
                #expect(try process.runCommand(["rename", target, "Tests"]).status == 0)
                #expect(try listedSummaries(of: process).first?.name == "Tests")
                #expect(try process.runCommand(["rename", target]).status == 0)
                #expect(try listedSummaries(of: process).first?.name == nil)
            }
        }
    }
}
