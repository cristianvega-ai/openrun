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

/// One attempt to detach while frames pile up in the connection of the tool.
private func detachWhileTheSessionWritesOutput(attempt: Int, identifier: String, process: RunningSessionProcess) async throws {
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

/// How many times `pattern` occurs in `bytes`, without overlaps.
private func occurrences(of pattern: String, in bytes: [UInt8]) -> Int {
    let pattern = Array(pattern.utf8)
    var count = 0
    var start = 0
    while start + pattern.count <= bytes.count {
        if bytes[start..<start + pattern.count].elementsEqual(pattern) {
            count += 1
            start += pattern.count
        } else {
            start += 1
        }
    }
    return count
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

        /// The documented price of the split-key hold: a lone Escape reaches the
        /// program at most 20 milliseconds later than another key. The test
        /// waits for the program to say it reads, and for each answer before the
        /// next key, and compares the Escape with a plain key typed the same way.
        @Test func aLoneEscapeReachesTheProgramAtMostTwentyMillisecondsLaterThanAPlainKey() async throws {
            try await RunningSessionProcess.run { process in
                // The program reports each key it reads as key-<hex>.
                let script = "stty raw -echo; printf 'key-reader-ready\\r\\n'; "
                    + "while :; do key=$(dd bs=1 count=1 2>/dev/null | od -An -tx1 | tr -d ' \\n'); printf 'key-%s\\r\\n' \"$key\"; done"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                defer { terminal.closeNow() }
                #expect(await eventually { terminal.isInRawMode })
                #expect(await terminal.waitForScreen(containing: "key-reader-ready"))

                var plainDelays: [Duration] = []
                var escapeDelays: [Duration] = []
                for _ in 0..<9 {
                    plainDelays.append(try #require(delayUntilReported(key: 0x71, in: terminal)))
                    escapeDelays.append(try #require(delayUntilReported(key: 0x1B, in: terminal)))
                }
                // Load only adds delay to a sample, so the smallest delays
                // show the hold. A longer hold raises every Escape sample.
                let plain = plainDelays.min()!
                let escape = escapeDelays.min()!
                print("lone-escape-delay: plain \(plain), escape \(escape), extra \(escape - plain)")
                // The hold is 20 ms. The rest of the allowance covers the
                // program's own commands, so a longer hold fails.
                #expect(escape - plain <= .milliseconds(40), "plain \(plainDelays), escape \(escapeDelays)")

                terminal.type(bytes: [0x1D])
                #expect(await terminal.waitForScreen(containing: "mode-restored"))
            }
        }

        /// The halves of a kitty Control-] arrive 20 ms apart at most, but the
        /// tool gets to the second half only later, as on a busy Mac. The hold
        /// counts from when the bytes were read, so the key still detaches.
        /// Stopping the tool between the halves makes it late on purpose.
        @Test func aKeyWhoseSecondHalfArrivesInTimeDetachesEvenWhenTheToolReadsItLate() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh"])
                var conclusiveRounds = 0
                for round in 0..<30 where conclusiveRounds == 0 {
                    let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                    defer { terminal.closeNow() }
                    guard try await typeAKeyInHalvesWhileTheToolStops(terminal) else {
                        print("hold-round-\(round): not conclusive")
                        continue
                    }
                    conclusiveRounds += 1
                    #expect(await terminal.waitForScreen(containing: "mode-restored", timeout: .seconds(10)), "round \(round)")
                    #expect(terminal.screenText.contains("[detached]"), "round \(round): \(terminal.screenText)")
                    #expect(terminal.screenText.contains("status=0"), "round \(round)")
                }
                #expect(conclusiveRounds == 1)
            }
        }

        /// Types the kitty Control-] in two halves, and stops the tool between
        /// them for 100 ms. Returns whether the round shows what the test is
        /// about: the tool read the first half before it stopped, and stopped
        /// before its 20 ms hold ended.
        private func typeAKeyInHalvesWhileTheToolStops(_ terminal: AttachedTerminal) async throws -> Bool {
            #expect(await eventually { terminal.isInRawMode })
            let tool = try #require(terminal.childProcessIdentifier(named: RunningSessionProcess.commandExecutable.lastPathComponent))
            let path = try #require(TerminalControl.terminalPath(ofProcess: tool))

            let typed = ContinuousClock.now
            terminal.type(bytes: Array("\u{1B}[93".utf8))
            // Stop the tool as soon as it has read the first half. A fixed
            // pause cannot tell this moment on a busy Mac. The tool can read
            // the half between two polls, so a quiet queue after 5 ms also
            // ends the wait. The checks below reject a round that is wrong.
            var sawFirstHalf = false
            while ContinuousClock.now - typed < .milliseconds(200) {
                let waitingNow = TerminalControl.waitingInput(onTerminal: path) ?? 0
                sawFirstHalf = sawFirstHalf || waitingNow > 0
                if waitingNow == 0 && (sawFirstHalf || ContinuousClock.now - typed > .milliseconds(5)) { break }
                usleep(50)
            }
            kill(tool, SIGSTOP)
            let stoppedAfter = ContinuousClock.now - typed
            terminal.type(bytes: Array(";5u".utf8))
            var waiting = 0
            for _ in 0..<200 where waiting < 3 {
                waiting = TerminalControl.waitingInput(onTerminal: path) ?? 0
                usleep(5_000)
            }
            // The stopped tool reads nothing, so only the second half waits
            // when the tool read the first half before it stopped.
            let firstHalfRead = TerminalControl.waitingInput(onTerminal: path) == 3
            usleep(100_000)
            kill(tool, SIGCONT)
            print("hold-round: stopped \(stoppedAfter) after the first half, first half read: \(firstHalfRead)")
            return firstHalfRead && stoppedAfter < .milliseconds(15)
        }

        /// A program that never reads input, and keys that keep coming. The
        /// keys that wait in the tool have a limit, so the tool stops reading
        /// the terminal instead of growing.
        @Test(.tags(.floodsTerminalInput)) func keysThatWaitForAProgramThatNeverReadsUseBoundedMemory() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "stty raw -echo; exec sleep 600"])
                let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                defer { terminal.closeNow() }
                #expect(await eventually { terminal.isInRawMode })
                let tool = try #require(terminal.childProcessIdentifier(named: RunningSessionProcess.commandExecutable.lastPathComponent))
                let path = try #require(TerminalControl.terminalPath(ofProcess: tool))
                let before = try #require(TerminalControl.memoryFootprint(of: tool))

                // 96 MiB, far more than the session process and the tool hold.
                let paste = [UInt8](repeating: UInt8(ascii: "x"), count: 64 * 1024)
                for _ in 0..<(96 * 16) { terminal.type(bytes: paste) }
                let limit = before + 40 * 1024 * 1024
                var largest = before
                var waitingSince: ContinuousClock.Instant?
                let deadline = ContinuousClock.now + .seconds(60)
                // The tool has stopped reading when keys wait in the terminal for a whole second.
                while ContinuousClock.now < deadline, largest <= limit {
                    largest = max(largest, TerminalControl.memoryFootprint(of: tool) ?? 0)
                    if (TerminalControl.waitingInput(onTerminal: path) ?? 0) > 0 {
                        let since = waitingSince ?? ContinuousClock.now
                        waitingSince = since
                        if ContinuousClock.now - since > .seconds(1) { break }
                    } else {
                        waitingSince = nil
                    }
                    try await Task.sleep(for: .milliseconds(20))
                }
                print("bounded-keys: footprint before \(before), largest \(largest)")
                #expect(largest <= limit, "the tool grew from \(before) to \(largest) bytes")
                #expect(waitingSince != nil, "the tool kept reading keys")

                // Attaching still ends at once, with the terminal restored.
                kill(tool, SIGTERM)
                #expect(await terminal.waitForScreen(containing: "mode-restored", timeout: .seconds(10)))
                #expect(terminal.screenText.contains("status=143"))
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
                let tool = try #require(terminal.childProcessIdentifier(named: RunningSessionProcess.commandExecutable.lastPathComponent))
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

        /// The window changes size after the title push of the first picture
        /// reached it. The picture is made again, and it must not push the
        /// title a second time, because the closing pops it only once.
        @Test func aResizeThatInterruptsThePictureLeavesNoExtraTitleOnTheStackOfTheWindow() async throws {
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
                let tool = try #require(terminal.childProcessIdentifier(named: RunningSessionProcess.commandExecutable.lastPathComponent))
                let path = try #require(TerminalControl.terminalPath(ofProcess: tool))
                #expect(await eventually { (TerminalControl.waitingOutput(onTerminal: path) ?? 0) >= 512 })

                // The tool waits with the picture half written. Its first bytes,
                // the title push, are in the queue of the terminal.
                try terminal.resize(columns: 70, rows: 20)
                try await Task.sleep(for: .milliseconds(300))
                terminal.resumeOutput()
                #expect(await terminal.waitForScreen(containing: "picture-line-22"))
                terminal.type(bytes: [0x1D])
                #expect(await terminal.waitForScreen(containing: "mode-restored"))

                let received = terminal.receivedBytes
                #expect(occurrences(of: "\u{1B}[22;0t", in: received) == occurrences(of: "\u{1B}[23;0t", in: received))
                #expect(occurrences(of: "\u{1B}[23;0t", in: received) == 1)
            }
        }

        @Test func detachingWhileTheSessionWritesOutputAlwaysReportsDetachedWithStatusZero() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "while :; do echo busy-output-line-$RANDOM; done"])
                // Each attempt has its own terminal and tool, so four can run
                // at once. The attempts do not depend on each other.
                for firstAttempt in stride(from: 0, to: 12, by: 4) {
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for attempt in firstAttempt..<firstAttempt + 4 {
                            group.addTask { try await detachWhileTheSessionWritesOutput(attempt: attempt, identifier: identifier, process: process) }
                        }
                        try await group.waitForAll()
                    }
                }
                #expect(try process.listedIdentifiers() == [identifier])
            }
        }

        @Test(.tags(.floodsTerminalInput)) func controlBracketDetachesWhileTypedKeysWaitForTheProgram() async throws {
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

        @Test func aResizeBeforeASuspensionAndAResumeKeepsTheLocalScreenAtTheSizeOfTheWindow() async throws {
            try await RunningSessionProcess.run { process in
                // The program prints when the session terminal has the new
                // size, and the tool resizes its local screen before it
                // sends that size. The line is longer than the new width.
                let longLine = "1234567890123456789012345678901234567890abcdefghijklmnopqrst"
                let program = """
                    while [ "$(stty size)" != "24 40" ]; do sleep 0.05; done
                    echo '\(longLine)'
                    printf MARK
                    exec cat
                    """
                let identifier = try process.createSession(program: ["/bin/sh", "-c", program])
                let terminal = try AttachedTerminal(shellScript: attachScript(identifier: identifier, process: process), folder: process.directory)
                defer { terminal.closeNow() }
                #expect(await eventually { terminal.isInRawMode })
                let tool = try #require(terminal.childProcessIdentifier(named: RunningSessionProcess.commandExecutable.lastPathComponent))

                // The system sends SIGWINCH to the tool, as it does for a window.
                try terminal.resize(columns: 40, rows: 24)
                #expect(await terminal.waitForScreen(containing: "MARK"))

                kill(tool, SIGTSTP)
                #expect(await eventually(timeout: .seconds(10)) { TerminalControl.isStopped(process: tool) })
                let beforeContinue = terminal.receivedBytes.count
                kill(tool, SIGCONT)
                #expect(await eventually { terminal.isInRawMode && terminal.receivedBytes.count > beforeContinue })
                // The picture of the local screen is on the window again.
                #expect(await terminal.waitForScreen(containing: "MARK"))

                terminal.type("X")
                #expect(await terminal.waitForScreen(containing: "MARKX"), "\(terminal.screenText)")
                let lines = terminal.screenText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                #expect(lines.prefix(3) == ["1234567890123456789012345678901234567890", "abcdefghijklmnopqrst", "MARKX"], "\(lines.prefix(4))")
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

                let tool = try #require(terminal.childProcessIdentifier(named: RunningSessionProcess.commandExecutable.lastPathComponent))
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

/// Types one key and returns how long its report, `key-<hex>`, took to come
/// back from the program, or `nil` after 3 seconds.
private func delayUntilReported(key: UInt8, in terminal: AttachedTerminal) -> Duration? {
    let report = Array(("key-" + String(format: "%02x", key) + "\r\n").utf8)
    let reportsBefore = occurrences(of: report, in: terminal.receivedBytes)
    let start = ContinuousClock.now
    terminal.type(bytes: [key])
    while ContinuousClock.now - start < .seconds(3) {
        if occurrences(of: report, in: terminal.receivedBytes) > reportsBefore {
            return ContinuousClock.now - start
        }
        usleep(250)
    }
    return nil
}

private func occurrences(of pattern: [UInt8], in bytes: [UInt8]) -> Int {
    guard bytes.count >= pattern.count else { return 0 }
    var count = 0
    var start = 0
    while start <= bytes.count - pattern.count {
        if bytes[start..<start + pattern.count].elementsEqual(pattern) {
            count += 1
            start += pattern.count
        } else {
            start += 1
        }
    }
    return count
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
