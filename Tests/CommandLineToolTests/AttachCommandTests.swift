import Darwin
import Foundation
import SessionProcessHarness
import Testing

extension CommandLineToolIntegration {
    @Suite struct AttachCommandTests {

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
