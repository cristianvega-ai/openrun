import Darwin
import Foundation
import SessionProcessHarness
import Testing

extension SessionProcessIntegration {
    /// The program of a session has the session's pseudo terminal as its
    /// controlling terminal. Without that, Control-C would do nothing and a
    /// shell could not run jobs.
    @Suite struct JobControlTests {
        private static let interrupt = "\u{03}"

        /// Types text into a session without attaching, as `openrun send` does.
        private static func type(_ text: String, into identifier: String, of process: RunningSessionProcess, pressEnter: Bool = false) throws {
            let result = try process.runCommand(["send", identifier] + (pressEnter ? ["--enter"] : []) + ["--", text])
            #expect(result.status == 0)
        }

        @Test func theProgramNamesTheSessionDeviceAsItsControllingTerminal() async throws {
            try await RunningSessionProcess.run { process in
                let script = "echo \"controlling=$(ps -o tty= -p $$ | tr -d ' ') standard=$(tty)\"; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "standard=/dev/"))
                let screen = try process.screenText(of: identifier)
                let device = try #require(screen.range(of: #"standard=/dev/(\S+)"#, options: .regularExpression).map { String(screen[$0]).dropFirst("standard=/dev/".count) })
                // ps names the controlling terminal without /dev/. A program
                // with no controlling terminal shows "??".
                #expect(device.hasPrefix("ttys"))
                #expect(screen.contains("controlling=\(device) "))
            }
        }

        @Test func controlCInterruptsAProgramThatIsNotAShell() async throws {
            try await RunningSessionProcess.run { process in
                // sleep never opens the terminal itself, so it has a
                // controlling terminal only when the launch gives it one.
                let identifier = try process.createSession(program: ["/bin/sleep", "30"])
                try await Task.sleep(for: .milliseconds(300))
                let clock = ContinuousClock()
                let start = clock.now
                try Self.type(Self.interrupt, into: identifier, of: process)
                let ended = await eventually(timeout: .seconds(2)) { ((try? process.listedIdentifiers()) ?? [identifier]).isEmpty }
                print("Control-C ended a bare sleep after \(clock.now - start)")
                #expect(ended)
            }
        }
    }
}
