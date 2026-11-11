import Foundation
import SessionProcessHarness
import Testing

/// A shell command that runs `openrun` with the socket of the process.
private func openrun(_ process: RunningSessionProcess, _ arguments: String) -> String {
    "'\(RunningSessionProcess.commandExecutable.path)' --socket '\(process.socketPath)' \(arguments)"
}

extension SessionProcessIntegration {
    /// The rule of 2026-10-15: a program acts freely on its own session, and
    /// typing into or reading another session needs the user's approval.
    @Suite struct CrossSessionRuleTests {
        @Test func aProgramInOneSessionCannotActOnAnother() async throws {
            try await RunningSessionProcess.run { process in
                let target = try process.createSession(program: ["/bin/sh"])
                // Each request must fail for this rule, and not for another
                // reason. attach keeps the terminal of the session, which it
                // needs, so only the errors go to the file.
                let errors = process.directory.appendingPathComponent("errors").path
                let script = [
                    "check() { name=$1; shift; \"$@\" 2>'\(errors)'; grep -q \"the user's approval\" '\(errors)' && echo $name=refused || echo $name=other; }",
                    "check send \(openrun(process, "send \(target) typed-from-elsewhere"))",
                    "check read \(openrun(process, "read \(target)"))",
                    "check attach \(openrun(process, "attach \(target)"))",
                    "check kill \(openrun(process, "kill \(target)"))",
                    "exec sleep 60",
                ].joined(separator: "; ")
                let caller = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: caller, containing: "kill="))
                let screen = try process.screenText(of: caller)
                for request in ["send", "read", "attach", "kill"] {
                    #expect(screen.contains("\(request)=refused"), "\(screen)")
                }
                #expect(try process.listedIdentifiers().contains(target))
                #expect(try !process.screenText(of: target).contains("typed-from-elsewhere"))
            }
        }
    }
}
