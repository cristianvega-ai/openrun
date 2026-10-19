import Darwin
import Foundation
import SessionProcessHarness
import Testing

/// A shell script that attaches to a session and reports what the terminal
/// looked like before and after. The script prints `status=` and
/// `mode-restored` or `mode-changed` when attaching ends.
private func attachScript(identifier: String, process: RunningSessionProcess) -> String {
    let executable = RunningSessionProcess.commandExecutable.path
    return """
        saved=$(stty -g)
        '\(executable)' attach \(identifier) --socket '\(process.socketPath)'
        code=$?
        echo "status=$code"
        if [ "$(stty -g)" = "$saved" ]; then echo mode-restored; else echo mode-changed; fi
        """
}

extension CommandLineToolIntegration {
    @Suite struct AttachCommandTests {
        @Test func attachDrawsTheScreenInRawModeRelaysKeysAndDetachesWithControlBracket() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "echo already-on-screen; exec /bin/sh"])
                #expect(await process.waitForScreen(of: identifier, containing: "already-on-screen"))
                let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                defer { terminal.closeNow() }

                // The picture of the session appears, and the terminal is in raw mode.
                #expect(await terminal.waitForScreen(containing: "already-on-screen"))
                #expect(await eventually { terminal.isInRawMode })

                // Keys reach the session, and its output comes back.
                terminal.type("echo keys-$((20+22))\r")
                #expect(await terminal.waitForScreen(containing: "keys-42"))

                // Control-] leaves, and the session goes on.
                terminal.type(bytes: [0x1D])
                #expect(await terminal.waitForScreen(containing: "mode-restored"))
                #expect(terminal.screenText.contains("status=0"))
                #expect(try process.listedIdentifiers() == [identifier])
                #expect(await terminal.waitForExit() == .exited(status: 0))
            }
        }

        /// The harness checked only two of the flags that raw
        /// mode clears, so a terminal that still turned Control-C into a signal
        /// counted as raw.
        @Test func theHarnessCallsATerminalRawOnlyWhenEveryFlagOfRawModeIsClear() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            // No line editing and no echo, but the signal keys, the carriage
            // return translation and the output processing stay on.
            let partial = try AttachedTerminal(shellScript: "stty -icanon -echo; echo partial-ready; sleep 60", folder: folder)
            defer { partial.closeNow() }
            let full = try AttachedTerminal(shellScript: "stty raw -echo; echo full-ready; sleep 60", folder: folder)
            defer { full.closeNow() }
            let fresh = try AttachedTerminal(shellScript: "echo fresh-ready; sleep 60", folder: folder)
            defer { fresh.closeNow() }

            #expect(await partial.waitForScreen(containing: "partial-ready"))
            #expect(await fresh.waitForScreen(containing: "fresh-ready"))
            #expect(await eventually { full.isInRawMode })
            #expect(!partial.isInRawMode)
            #expect(!fresh.isInRawMode)
            #expect(full.isInRawMode)
        }

        /// The reply handler of the harness terminal held the
        /// terminal itself, so every instance leaked its screen.
        @Test func aHarnessTerminalIsFreedWhenTheTestLetsGoOfIt() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            weak var reference: AttachedTerminal?
            do {
                let terminal = try AttachedTerminal(shellScript: "echo running; printf '\\033[c'; sleep 60", folder: folder)
                reference = terminal
                #expect(await terminal.waitForScreen(containing: "running"))
                #expect(await eventually { terminal.repliesSent >= 1 })
                terminal.closeNow()
            }
            #expect(await eventually(timeout: .seconds(10)) { reference == nil }, "the terminal is still alive")
        }
    }
}
