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

        @Test func controlCInterruptsTheForegroundJob() async throws {
            try await RunningSessionProcess.run { process in
                // The trap lets the shell survive the interrupt that ends sleep.
                // No other test or program sleeps for this many seconds, and
                // the search below looks only below the shell of the session.
                let script = "trap ':' INT; echo STARTED shell=$$; sleep \(Self.jobSleepDuration); echo status=$?; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "STARTED shell="))
                let screen = try process.screenText(of: identifier)
                let shell = try #require(screen.range(of: #"STARTED shell=(\d+)"#, options: .regularExpression).flatMap { pid_t(screen[$0].dropFirst("STARTED shell=".count)) })
                // Sleep must run before the interrupt, or the shell takes it.
                #expect(await eventually { Self.runs(command: "sleep \(Self.jobSleepDuration)", below: shell) })

                let clock = ContinuousClock()
                let start = clock.now
                try Self.type(Self.interrupt, into: identifier, of: process)
                let interrupted = await process.waitForScreen(of: identifier, containing: "status=130", timeout: .seconds(2))
                let elapsed = clock.now - start
                print("Control-C interrupted the foreground sleep after \(elapsed)")
                #expect(interrupted)
                #expect(elapsed < .seconds(2))
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

        /// A duration that no other test or program uses, so that the job of
        /// this test cannot be mistaken for another one.
        private static let jobSleepDuration = "31.4159"

        /// Whether a process with exactly this command line runs below the
        /// process, as a child, a grandchild and so on. A process elsewhere on
        /// the machine never counts.
        private static func runs(command: String, below ancestor: pid_t) -> Bool {
            let listCommand = Process()
            listCommand.executableURL = URL(fileURLWithPath: "/bin/ps")
            listCommand.arguments = ["-A", "-o", "pid=,ppid=,command="]
            let pipe = Pipe()
            listCommand.standardOutput = pipe
            guard (try? listCommand.run()) != nil else { return false }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            listCommand.waitUntilExit()

            var parents: [pid_t: pid_t] = [:]
            var matching: [pid_t] = []
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard fields.count == 3, let identifier = pid_t(fields[0]), let parent = pid_t(fields[1]) else { continue }
                parents[identifier] = parent
                if fields[2].trimmingCharacters(in: .whitespaces) == command { matching.append(identifier) }
            }
            return matching.contains { candidate in
                var current = candidate
                // The chain is short. The limit only guards against a cycle.
                for _ in 0..<64 {
                    guard let parent = parents[current] else { return false }
                    if parent == ancestor { return true }
                    current = parent
                }
                return false
            }
        }
    }
}
