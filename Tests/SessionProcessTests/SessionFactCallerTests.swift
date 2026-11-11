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

        @Test func aProgramAlertsItsOwnSessionAndNoOther() async throws {
            try await RunningSessionProcess.run { process in
                let target = try process.createSession(program: ["/bin/sh", "-c", "exec sleep 60"])
                let script = [
                    "\(openrun(process, "notify --session \(target) taken")) 2>&1; echo other=$?",
                    "\(openrun(process, "notify Build done")); echo own=$?",
                    "exec sleep 60",
                ].joined(separator: "; ")
                let watcher = try SessionChangeWatcher(process)
                let caller = try process.createSession(program: ["/bin/sh", "-c", script])
                let alerted = watcher.summary(of: caller) { $0.alert != nil }
                #expect(alerted?.alert?.text == "Build done" && alerted?.alert?.source == .notifyCommand)
                let screen = try process.screenText(of: caller)
                #expect(screen.contains("other=1") && screen.contains("own=0"), "\(screen)")
                #expect(try listedSummaries(of: process).first { $0.identifierText == target }?.alert == nil)
            }
        }

        /// Without a session process, the alert goes to the terminal as OSC
        /// 777, and the session process of the terminal reads it there.
        @Test func anAlertWithoutASessionProcessGoesToTheTerminal() async throws {
            try await RunningSessionProcess.run { process in
                let missing = process.directory.appendingPathComponent("missing.socket").path
                let tool = "'\(RunningSessionProcess.commandExecutable.path)' --socket '\(missing)'"
                let watcher = try SessionChangeWatcher(process)
                let caller = try process.createSession(program: ["/bin/sh", "-c", "\(tool) notify Tests passed; echo status=$?; exec sleep 60"])
                let alerted = watcher.summary(of: caller) { $0.alert != nil }
                #expect(alerted?.alert?.text == "Tests passed" && alerted?.alert?.source == .terminalNotification)
                #expect(await process.waitForScreen(of: caller, containing: "status=0"))
            }
        }

        /// Exit code 2 would block the action of a hook of Claude Code.
        @Test func wrongArgumentsOfNotifyExitWithOne() async throws {
            try await RunningSessionProcess.run { process in
                let statuses = try [["notify"], ["notify", "--bogus", "text"], ["list", "--bogus"]].map { try process.runCommand($0).status }
                #expect(statuses == [1, 1, 2])
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
