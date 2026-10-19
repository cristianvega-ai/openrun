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

        /// A program that is on the alternate screen when a client attaches.
        /// The picture of the session is drawn on the alternate screen, and
        /// detaching leaves it, so the user is back on the screen that they
        /// started from.
        @Test func attachingWhileTheProgramIsOnTheAlternateScreenDrawsItThereAndDetachLeavesIt() async throws {
            try await RunningSessionProcess.run { process in
                let program = "printf '\\033[?1049h\\033[2J\\033[Halternate-text'; exec /bin/sh"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", program])
                #expect(await process.waitForScreen(of: identifier, containing: "alternate-text"))
                let script = "echo primary-before-attach; " + attachScript(identifier: identifier, process: process)
                let terminal = try AttachedTerminal(shellScript: script, folder: process.directory)
                defer { terminal.closeNow() }

                #expect(await terminal.waitForScreen(containing: "alternate-text"))
                #expect(await eventually { terminal.isInRawMode })
                #expect(terminal.isAlternateScreenActive, "the picture is not on the alternate screen: \(terminal.screenText)")
                #expect(!terminal.screenText.contains("primary-before-attach"))
                let beforeDetach = terminal.receivedBytes.count

                terminal.type(bytes: [0x1D])
                #expect(await terminal.waitForScreen(containing: "mode-restored"))
                // The terminal left the alternate screen after the detach, and
                // shows the screen that it had before.
                #expect(!terminal.isAlternateScreenActive, "the terminal is still on the alternate screen: \(terminal.screenText)")
                let afterDetach = Array(terminal.receivedBytes.dropFirst(beforeDetach))
                #expect(String(decoding: afterDetach, as: UTF8.self).contains("\u{1B}[?1049l"))
                #expect(terminal.screenText.contains("primary-before-attach"))
                #expect(terminal.screenText.contains("status=0"))
                #expect(!terminal.screenText.contains("alternate-text"))
                // The program is still on the alternate screen, in its session.
                #expect(try process.listedIdentifiers() == [identifier])
                #expect(try process.screenText(of: identifier).contains("alternate-text"))
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

        @Test func theKittyFormOfControlBracketDetaches() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh"])
                let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                defer { terminal.closeNow() }
                #expect(await eventually { terminal.isInRawMode })

                // A terminal sends this once a program turns on the kitty keyboard protocol.
                terminal.type(bytes: Array("\u{1B}[93;5u".utf8))
                #expect(await terminal.waitForScreen(containing: "mode-restored"))
                #expect(terminal.screenText.contains("[detached]"))
                #expect(terminal.screenText.contains("status=0"))
                #expect(try process.listedIdentifiers() == [identifier])
                #expect(await terminal.waitForExit() == .exited(status: 0))
            }
        }

        @Test func aKittyKeyTypedInTwoWritesFiveMillisecondsApartStillDetaches() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh"])
                let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                defer { terminal.closeNow() }
                #expect(await eventually { terminal.isInRawMode })

                // Over ssh or in a multiplexer, one key can arrive in two reads.
                terminal.type(bytes: Array("\u{1B}[93".utf8))
                try await Task.sleep(for: .milliseconds(5))
                terminal.type(bytes: Array(";5u".utf8))
                #expect(await terminal.waitForScreen(containing: "mode-restored"))
                #expect(terminal.screenText.contains("[detached]"))
                #expect(terminal.screenText.contains("status=0"))
                #expect(try process.listedIdentifiers() == [identifier])
                #expect(await terminal.waitForExit() == .exited(status: 0))
            }
        }

        /// The window changes size while the first picture waits for the
        /// terminal. The session must still get the new size.
        @Test func aResizeWhileTheFirstPictureWaitsReachesTheSession() async throws {
            try await RunningSessionProcess.run { process in
                let program = """
                    number=0
                    while [ $number -lt 23 ]; do
                      printf 'picture-line-%02d-%s\\n' $number 'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefgh'
                      number=$((number+1))
                    done
                    exec /bin/sh
                    """
                let identifier = try process.createSession(program: ["/bin/sh", "-c", program])
                #expect(await process.waitForScreen(of: identifier, containing: "picture-line-22"))
                let terminal = try AttachedTerminal(
                    shellScript: attachScript(identifier: identifier, process: process),
                    columns: 100,
                    rows: 30,
                    folder: process.directory
                )
                terminal.pauseOutput()
                defer {
                    terminal.resumeOutput()
                    terminal.closeNow()
                }
                #expect(await eventually { terminal.isInRawMode })
                let tool = try #require(terminal.childProcessIdentifiers().first)
                let path = try #require(TerminalControl.terminalPath(ofProcess: tool))
                #expect(await eventually { (TerminalControl.waitingOutput(onTerminal: path) ?? 0) >= 512 })

                try terminal.resize(columns: 70, rows: 20)
                try await Task.sleep(for: .milliseconds(100))
                terminal.resumeOutput()
                #expect(await eventually {
                    terminal.type("stty size\r")
                    try? await Task.sleep(for: .milliseconds(150))
                    return terminal.screenText.contains("20 70")
                })
                terminal.type(bytes: [0x1D])
                #expect(await terminal.waitForScreen(containing: "mode-restored"))
            }
        }

        @Test func detachingWhileTheSessionWritesOutputAlwaysReportsDetachedWithStatusZero() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "while :; do echo busy-output-line-$RANDOM; done"])
                for attempt in 0..<12 {
                    let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                    defer { terminal.closeNow() }
                    #expect(await eventually { terminal.isInRawMode })
                    // Let output flow, then stop reading it for a while, as a slow
                    // terminal window does. The tool blocks while it draws a frame,
                    // and more frames pile up in its connection. Then let output
                    // flow again and type the key at once. The relay loop is then
                    // reading the piled-up frames, so the key arrives while it is
                    // in the middle of one, which is when the detach used to be
                    // reported as a lost connection. The terminal must not hold
                    // output back while the key is typed: the key would not reach
                    // the tool at that moment, and the race would not happen.
                    try await Task.sleep(for: .milliseconds(100))
                    terminal.pauseOutput()
                    try await Task.sleep(for: .milliseconds(300))
                    terminal.resumeOutput()
                    terminal.type(bytes: [0x1D])
                    #expect(await terminal.waitForScreen(containing: "mode-restored"), "attempt \(attempt)")
                    #expect(terminal.screenText.contains("status=0"), "attempt \(attempt)")
                    #expect(terminal.screenText.contains("[detached]"), "attempt \(attempt)")
                    #expect(!terminal.screenText.contains("connection lost"), "attempt \(attempt)")
                }
                #expect(try process.listedIdentifiers() == [identifier])
            }
        }

        @Test func controlBracketDetachesWhileTypedKeysWaitForTheProgram() async throws {
            try await RunningSessionProcess.run { process in
                // The program never reads, so typed keys pile up until the
                // session process holds as much as it may and the sends wait.
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "stty raw -echo; exec sleep 600"])
                let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                defer { terminal.closeNow() }
                #expect(await eventually { terminal.isInRawMode })

                // 16 MiB is more than the session process holds for one program.
                let paste = [UInt8](repeating: UInt8(ascii: "x"), count: 64 * 1024)
                for _ in 0..<256 { terminal.type(bytes: paste) }
                terminal.type(bytes: [0x1D])
                #expect(await terminal.waitForScreen(containing: "mode-restored", timeout: .seconds(30)))
                #expect(terminal.screenText.contains("[detached]"))
                #expect(terminal.screenText.contains("status=0"))
                #expect(try process.listedIdentifiers() == [identifier])
            }
        }

        @Test func aDetachedAndReattachedTerminalShowsTheSameScreen() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "seq 1 40; echo end-of-numbers; sleep 60"])
                #expect(await process.waitForScreen(of: identifier, containing: "end-of-numbers"))
                let expected = try process.screenText(of: identifier).trimmingCharacters(in: .whitespacesAndNewlines)

                for _ in 0..<2 {
                    let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                    defer { terminal.closeNow() }
                    #expect(await terminal.waitForScreen(containing: "end-of-numbers"))
                    #expect(terminal.screenText.trimmingCharacters(in: .whitespacesAndNewlines) == expected)
                    terminal.type(bytes: [0x1D])
                    #expect(await terminal.waitForScreen(containing: "mode-restored"))
                }
            }
        }

        @Test func theSessionTerminalHasTheSizeOfTheAttachedTerminalAlsoAfterAResize() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh"])
                let terminal = try AttachedTerminal(
                    shellScript: attachScript(identifier: identifier, process: process),
                    columns: 100,
                    rows: 30,
                    folder: process.directory
                )
                defer { terminal.closeNow() }
                #expect(await eventually { terminal.isInRawMode })

                terminal.type("stty size\r")
                #expect(await terminal.waitForScreen(containing: "30 100"))

                try terminal.resize(columns: 60, rows: 20)
                // The window change reaches the session through the tool.
                #expect(await eventually {
                    terminal.type("stty size\r")
                    try? await Task.sleep(for: .milliseconds(150))
                    return terminal.screenText.contains("20 60")
                })
                terminal.type(bytes: [0x1D])
                #expect(await terminal.waitForScreen(containing: "mode-restored"))
            }
        }

        @Test func attachEndsAndRestoresTheModeWhenTheProgramExits() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "read line; exit 7"])
                let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                defer { terminal.closeNow() }
                #expect(await eventually { terminal.isInRawMode })

                terminal.type("go\r")
                #expect(await terminal.waitForScreen(containing: "mode-restored"))
                // The exit status of the program is the status of the tool.
                #expect(terminal.screenText.contains("status=7"))
                #expect(await eventually { ((try? process.listedIdentifiers()) ?? [identifier]).isEmpty })
            }
        }

        @Test(arguments: [SIGTERM, SIGHUP, SIGINT, SIGQUIT])
        func attachRestoresTheModeWhenItReceivesAStopSignal(signal: Int32) async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh"])
                let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                defer { terminal.closeNow() }
                #expect(await eventually { terminal.isInRawMode })

                let children = terminal.childProcessIdentifiers()
                let tool = try #require(children.first)
                kill(tool, signal)
                #expect(await terminal.waitForScreen(containing: "mode-restored"))
                #expect(terminal.screenText.contains("status=\(128 + signal)"))
                // Stopping the tool leaves the session running.
                #expect(try process.listedIdentifiers() == [identifier])
            }
        }

        /// The program writes the first part, waits for a line, and then writes
        /// the second part. `openrun attach` draws its first picture in between,
        /// inside an escape sequence or a UTF-8 character.
        @Test(arguments: [
            UnfinishedOutput(firstPart: "\\033[3", secondPart: "1mRED\\033[0m after", shown: "RED after", styled: "\u{1B}[38;5;1mRED"),
            UnfinishedOutput(firstPart: "\\342\\202", secondPart: "\\254 after", shown: "\u{20AC} after", styled: nil),
        ])
        func aPictureDrawnInsideAnUnfinishedSequenceLetsTheOutputFinishIt(output: UnfinishedOutput) async throws {
            try await RunningSessionProcess.run { process in
                let script = "stty -echo; printf 'before\\n\(output.firstPart)'; read line; printf '\(output.secondPart)\\n'; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "before"))
                let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                defer { terminal.closeNow() }
                #expect(await terminal.waitForScreen(containing: "before"))
                #expect(await eventually { terminal.isInRawMode })

                #expect(try process.runCommand(["send", identifier, "--enter", "go"]).status == 0)
                #expect(await terminal.waitForScreen(containing: "after"))
                // Without the start of the sequence, the terminal would show its
                // tail, such as "1mRED", as text.
                #expect(terminal.screenText.contains("before\n" + output.shown), "screen: \(terminal.screenText)")
                if let styled = output.styled {
                    #expect(terminal.screenWithStyles.contains(styled))
                }
                terminal.type(bytes: [0x1D])
                #expect(await terminal.waitForScreen(containing: "mode-restored"))
            }
        }

        /// The program leaves a sequence or a string open in the terminal window.
        /// Detaching must end it, or the terminal would take the reset
        /// sequences, and maybe the message, as part of it.
        @Test(arguments: [
            OpenSequence(kind: "control sequence", start: "\\033[3"),
            OpenSequence(kind: "operating system command", start: "\\033]0;open-title"),
            OpenSequence(kind: "device control string", start: "\\033Pzopen-device-string"),
        ])
        func detachingInsideAnOpenSequenceEndsItAndRestoresTheTerminal(sequence: OpenSequence) async throws {
            try await RunningSessionProcess.run { process in
                // Bracketed paste on and the cursor hidden, then the open sequence.
                let script = "stty -echo; printf '\\033[?2004h\\033[?25l'; read line; printf 'sequence-opened\\n\(sequence.start)'; sleep 60"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                defer { terminal.closeNow() }
                #expect(await eventually { terminal.isInRawMode })
                #expect(try process.runCommand(["send", identifier, "--enter", "go"]).status == 0)
                #expect(await terminal.waitForScreen(containing: "sequence-opened"))
                #expect(terminal.screenWithStyles.contains("\u{1B}[?2004h"))

                terminal.type(bytes: [0x1D])
                #expect(await terminal.waitForScreen(containing: "mode-restored"))
                #expect(terminal.screenText.contains("[detached]"), "\(sequence.kind): \(terminal.screenText)")
                #expect(terminal.screenText.contains("status=0"))
                #expect(!terminal.screenWithStyles.contains("\u{1B}[?2004h"))
                #expect(!terminal.screenWithStyles.contains("\u{1B}[?25l"))

                // The first bytes after the open sequence end it: CAN aborts a
                // sequence, and ST ends a string.
                let received = terminal.receivedBytes
                let opened = Array("sequence-opened".utf8)
                let start = try #require(lastRange(of: opened, in: received)).upperBound
                let afterSequence = Array(received[start...])
                let expectedStart = Array("\r\n".utf8) + sequence.startBytes
                #expect(Array(afterSequence.prefix(expectedStart.count)) == expectedStart)
                let closing = afterSequence.dropFirst(expectedStart.count)
                #expect(Array(closing.prefix(3)) == [0x18, 0x1B, 0x5C], "\(sequence.kind): \(Array(closing.prefix(12)))")
            }
        }

        @Test func attachWithoutATerminalFailsWithAMessage() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh"])
                let result = try process.runCommand(["attach", identifier])
                #expect(result.status == 1)
                #expect(result.standardError.contains("needs a terminal"))
            }
        }

        @Test func attachToAnUnknownSessionFailsBeforeChangingTheTerminal() async throws {
            try await RunningSessionProcess.run { process in
                let terminal = try AttachedTerminal(
                    shellScript: attachScript(identifier: "ffffffff", process: process),
                    folder: process.directory
                )
                defer { terminal.closeNow() }
                #expect(await terminal.waitForScreen(containing: "mode-restored"))
                #expect(terminal.screenText.contains("No session"))
                #expect(terminal.screenText.contains("status=1"))
            }
        }
    }
}

/// Output that a program writes in two parts, with the first picture of
/// `openrun attach` in between.
struct UnfinishedOutput: Sendable, CustomTestStringConvertible {
    /// The parts, as `printf` format text.
    var firstPart: String
    var secondPart: String
    /// Text that the terminal must show once both parts arrived.
    var shown: String
    /// Sequences that must come right before the text, for a style.
    var styled: String?

    var testDescription: String { firstPart }
}

/// A sequence or string that a program leaves open.
struct OpenSequence: Sendable, CustomTestStringConvertible {
    var kind: String
    /// The start, as `printf` format text.
    var start: String

    /// The bytes that `printf` writes for `start`.
    var startBytes: [UInt8] {
        Array(start.replacingOccurrences(of: "\\033", with: "\u{1B}").utf8)
    }

    var testDescription: String { kind }
}

/// Where `pattern` last occurs in `bytes`.
private func lastRange(of pattern: [UInt8], in bytes: [UInt8]) -> Range<Int>? {
    guard bytes.count >= pattern.count else { return nil }
    for start in stride(from: bytes.count - pattern.count, through: 0, by: -1)
    where bytes[start..<start + pattern.count].elementsEqual(pattern) {
        return start..<start + pattern.count
    }
    return nil
}
