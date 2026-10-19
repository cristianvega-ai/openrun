import Darwin
import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

@testable import CommandLineTool

/// A shell script that attaches to a session and reports how attaching
/// ended: `status=` and `mode-restored` or `mode-changed`, on the terminal
/// and, first, in the file `report` when there is one. A terminal that took
/// no output may still be inside a sequence that the tool could not end, so
/// the file is the report that a test can always read. `redirections` go
/// after the command, and `afterwards` runs after the report.
private func restoreScript(
    identifier: String,
    socketPath: String,
    report: URL? = nil,
    redirections: String = "",
    afterwards: String = ""
) -> String {
    let executable = RunningSessionProcess.commandExecutable.path
    let reportLine = report.map { "echo \"status=$code $mode\" > '\($0.path)'" } ?? ""
    return """
        saved=$(stty -g)
        '\(executable)' attach \(identifier) --socket '\(socketPath)' \(redirections)
        code=$?
        if [ "$(stty -g)" = "$saved" ]; then mode=mode-restored; else mode=mode-changed; fi
        \(reportLine)
        echo "status=$code"
        echo "$mode"
        \(afterwards)
        """
}

/// The report that `restoreScript` wrote, once it is there.
private func reportText(_ report: URL) async -> String {
    var text = ""
    _ = await eventually(timeout: .seconds(15)) {
        text = (try? String(contentsOf: report, encoding: .utf8)) ?? ""
        return text.hasSuffix("\n")
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private let controlBracket: [UInt8] = [0x1D]
private let endOfOpenSequence: [UInt8] = [0x18, 0x1B, 0x5C]

/// Where `pattern` last occurs in `bytes`.
private func lastIndex(of pattern: [UInt8], in bytes: [UInt8]) -> Int? {
    guard bytes.count >= pattern.count else { return nil }
    for start in stride(from: bytes.count - pattern.count, through: 0, by: -1)
    where bytes[start..<start + pattern.count].elementsEqual(pattern) {
        return start
    }
    return nil
}

/// Where `pattern` first occurs in `bytes`.
private func firstIndex(of pattern: [UInt8], in bytes: some Collection<UInt8>) -> Int? {
    let bytes = Array(bytes)
    guard bytes.count >= pattern.count else { return nil }
    for start in 0...(bytes.count - pattern.count) where bytes[start..<start + pattern.count].elementsEqual(pattern) {
        return start
    }
    return nil
}

private func contains(_ text: String, in bytes: some Collection<UInt8>) -> Bool {
    firstIndex(of: Array(text.utf8), in: bytes) != nil
}
extension CommandLineToolIntegration {
    @Suite struct AttachRestoreTests {
        /// The process identifier of `openrun attach`, the child of the script's shell.
        private func attachProcess(of terminal: AttachedTerminal) async -> pid_t? {
            var found: pid_t?
            _ = await eventually(timeout: .seconds(10)) {
                found = terminal.childProcessIdentifiers().first
                return found != nil
            }
            return found
        }

        @Test func aTerminateSignalWhileOutputFlowsLeavesTheAlternateScreenAndRestoresTheMode() async throws {
            try await RunningSessionProcess.run { process in
                let program = "printf '\\033[?1049h'; while :; do echo busy-output-line-$RANDOM; done"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", program])
                for round in 0..<4 {
                    let terminal = try AttachedTerminal(shellScript: restoreScript(identifier: identifier, socketPath: process.socketPath), folder: process.directory)
                    defer { terminal.closeNow() }
                    let tool = try #require(await attachProcess(of: terminal))
                    #expect(await eventually { terminal.isInRawMode }, "round \(round)")
                    #expect(await terminal.waitForScreen(containing: "busy-output-line"), "round \(round)")

                    kill(tool, SIGTERM)
                    // A second signal while the first one ends attaching must not
                    // change the exit code or write a second ending.
                    if round > 1 { kill(tool, SIGINT) }
                    #expect(await terminal.waitForScreen(containing: "mode-"), "round \(round)")
                    #expect(terminal.screenText.contains("mode-restored"), "round \(round): \(terminal.screenText)")
                    #expect(terminal.screenText.contains("status=143"), "round \(round): \(terminal.screenText)")

                    // After the closing sequences, no output of the program reaches
                    // the terminal, and the alternate screen is left.
                    let received = terminal.receivedBytes
                    let closing = try #require(lastIndex(of: endOfOpenSequence, in: received), "round \(round)")
                    let afterClosing = received[closing...]
                    #expect(contains("\u{1B}[?1049l", in: afterClosing), "round \(round)")
                    #expect(!contains("busy-output", in: afterClosing), "round \(round): \(String(decoding: afterClosing.prefix(200), as: UTF8.self))")
                }
                #expect(try process.listedIdentifiers() == [identifier])
            }
        }

        /// The terminal window stops taking output, as a frozen `ssh` or a
        /// paused multiplexer does, while the program writes without end.
        @Test(arguments: [EndingRequest.detachKey, .terminateSignal])
        func attachEndsAndRestoresTheModeWhileTheTerminalTakesNoOutput(request: EndingRequest) async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "while :; do echo busy-output-line-$RANDOM; done"])
                let report = process.directory.appendingPathComponent("report")
                let script = restoreScript(identifier: identifier, socketPath: process.socketPath, report: report)
                let terminal = try AttachedTerminal(shellScript: script, folder: process.directory)
                defer {
                    terminal.resumeOutput()
                    terminal.closeNow()
                }
                let tool = try #require(await attachProcess(of: terminal))
                #expect(await eventually { terminal.isInRawMode })
                #expect(await terminal.waitForScreen(containing: "busy-output-line"))
                let path = try #require(TerminalControl.terminalPath(ofProcess: tool))

                terminal.pauseOutput()
                // The terminal's output queue fills up, and the tool waits to write.
                #expect(await eventually { (TerminalControl.waitingOutput(onTerminal: path) ?? 0) >= 512 })
                switch request {
                case .detachKey: terminal.type(bytes: controlBracket)
                case .terminateSignal: kill(tool, SIGTERM)
                }

                // The tool ends and gives the mode back while the output is still stopped.
                #expect(await eventually(timeout: .seconds(10)) { !TerminalControl.exists(process: tool) }, "\(request)")
                #expect(!terminal.isInRawMode, "\(request)")
                #expect(await reportText(report) == "status=\(request.exitCode) mode-restored", "\(request)")
                #expect(try process.listedIdentifiers() == [identifier])
            }
        }

        @Test func aStopSignalSuspendsWithTheTerminalRestoredAndAContinueSignalDrawsTheSessionAgain() async throws {
            try await RunningSessionProcess.run { process in
                let program = "printf '\\033[?1049h'; echo on-the-alternate-screen; exec /bin/sh"
                let identifier = try process.createSession(program: ["/bin/sh", "-c", program])
                let terminal = try AttachedTerminal(shellScript: restoreScript(identifier: identifier, socketPath: process.socketPath), folder: process.directory)
                defer { terminal.closeNow() }
                let tool = try #require(await attachProcess(of: terminal))
                #expect(await eventually { terminal.isInRawMode })
                #expect(await terminal.waitForScreen(containing: "on-the-alternate-screen"))

                let beforeStop = terminal.receivedBytes.count
                kill(tool, SIGTSTP)
                // The tool stops, and the terminal is as it was before attaching.
                #expect(await eventually(timeout: .seconds(10)) { TerminalControl.isStopped(process: tool) })
                #expect(await eventually(timeout: .seconds(2)) { !terminal.isInRawMode })
                #expect(contains("\u{1B}[?1049l", in: terminal.receivedBytes.dropFirst(beforeStop)))
                // The title goes back when the terminal is restored, and is saved again on the continue.
                #expect(contains("\u{1B}[23;0t", in: terminal.receivedBytes.dropFirst(beforeStop)))

                let beforeContinue = terminal.receivedBytes.count
                kill(tool, SIGCONT)
                // Raw mode again, and the screen of the session again, on the alternate screen.
                #expect(await eventually { terminal.isInRawMode })
                #expect(await eventually {
                    let drawn = terminal.receivedBytes.dropFirst(beforeContinue)
                    return contains("\u{1B}[?1049h", in: drawn) && contains("on-the-alternate-screen", in: drawn)
                        && contains("\u{1B}[22;0t", in: drawn)
                })
                terminal.type("echo after-continue-$((40+2))\r")
                #expect(await terminal.waitForScreen(containing: "after-continue-42"))

                terminal.type(bytes: controlBracket)
                #expect(await terminal.waitForScreen(containing: "mode-"))
                #expect(terminal.screenText.contains("mode-restored"), "\(terminal.screenText)")
                #expect(terminal.screenText.contains("status=0"), "\(terminal.screenText)")
            }
        }

        /// Keys typed before attaching and while leaving stay for the program
        /// that reads the terminal next.
        @Test func rawModeKeepsTheKeysTypedAheadWhenItStartsAndWhenItEnds() throws {
            let spare = try TerminalControl.SpareTerminal()
            let descriptor = open(spare.path, O_RDWR | O_NOCTTY)
            try #require(descriptor >= 0)
            defer { close(descriptor) }
            // Without echo, no output waits for a window that this test does not have.
            var settings = termios()
            tcgetattr(descriptor, &settings)
            settings.c_lflag &= ~tcflag_t(ECHO)
            tcsetattr(descriptor, TCSANOW, &settings)

            spare.type(Array("before".utf8))
            let mode = try RawTerminalMode(descriptor: descriptor)
            #expect(TerminalControl.waitingInput(onTerminal: spare.path) == 6)

            spare.type(Array("after\n".utf8))
            mode.restore()
            #expect(TerminalControl.waitingInput(onTerminal: spare.path) == 12)
        }

        /// The keyboard thread reads no key while it is paused, and the keys
        /// stay in the terminal. `resume` lets it read them, and `stop` ends
        /// it while it is paused.
        @Test func pausedKeyboardThreadLeavesTheKeysInTheTerminalUntilItResumes() async throws {
            let spare = try TerminalControl.SpareTerminal()
            let descriptor = open(spare.path, O_RDWR | O_NOCTTY)
            try #require(descriptor >= 0)
            defer { close(descriptor) }
            var settings = termios()
            tcgetattr(descriptor, &settings)
            settings.c_lflag &= ~tcflag_t(ECHO)
            tcsetattr(descriptor, TCSANOW, &settings)
            let mode = try RawTerminalMode(descriptor: descriptor)
            defer { mode.restore() }

            let (clientSide, sessionSide) = try MessageConnection.makePair()
            let counter = ReceivedKeyCounter()
            let receiver = Thread {
                while let message = try? sessionSide.receive(ClientMessage.self) {
                    if case .input(let keys) = message { counter.add(keys.count) }
                }
            }
            receiver.start()
            let sender = KeySender(connection: clientSide, inputDescriptor: descriptor)
            sender.start(onDetach: {})
            try await Task.sleep(for: .milliseconds(150))

            sender.pause()
            spare.type(Array("while-paused".utf8))
            try await Task.sleep(for: .milliseconds(400))
            #expect(counter.total == 0, "the session got keys while the reading was paused")
            #expect(TerminalControl.waitingInput(onTerminal: spare.path) == 12)

            sender.resume()
            #expect(await eventually { counter.total == 12 })

            sender.pause()
            sender.stop()
            spare.type(Array("after-stop".utf8))
            try await Task.sleep(for: .milliseconds(300))
            #expect(counter.total == 12)
            #expect(TerminalControl.waitingInput(onTerminal: spare.path) == 10)
            clientSide.shutdown()
            sessionSide.shutdown()
        }

        /// A key that arrives after `stop` is for the next reader of the terminal,
        /// the shell. The keyboard thread may be inside its wait for keys when
        /// `stop` lands, and it used to read the key and drop it.
        @Test func keysTypedAfterTheKeyboardThreadWasStoppedStayInTheTerminal() async throws {
            let spare = try TerminalControl.SpareTerminal()
            let descriptor = open(spare.path, O_RDWR | O_NOCTTY)
            try #require(descriptor >= 0)
            defer { close(descriptor) }
            var settings = termios()
            tcgetattr(descriptor, &settings)
            settings.c_lflag &= ~tcflag_t(ECHO)
            tcsetattr(descriptor, TCSANOW, &settings)
            let mode = try RawTerminalMode(descriptor: descriptor)
            defer { mode.restore() }

            let (clientSide, sessionSide) = try MessageConnection.makePair()
            let counter = ReceivedKeyCounter()
            let receiver = Thread {
                while let message = try? sessionSide.receive(ClientMessage.self) {
                    if case .input(let keys) = message { counter.add(keys.count) }
                }
            }
            receiver.start()
            let sender = KeySender(connection: clientSide, inputDescriptor: descriptor)
            sender.start(onDetach: {})

            // Keys typed while the thread runs reach the session.
            spare.type(Array("before-stop".utf8))
            #expect(await eventually { counter.total == 11 })

            sender.stop()
            let sentBeforeStop = counter.total
            // The thread is inside its wait for keys now. These keys come later.
            for _ in 0..<5 {
                spare.type(Array("after-stop".utf8))
                try await Task.sleep(for: .milliseconds(30))
            }
            try await Task.sleep(for: .milliseconds(300))

            #expect(counter.total == sentBeforeStop, "the session got keys that were typed after the stop")
            #expect(TerminalControl.waitingInput(onTerminal: spare.path) == 50)
            clientSide.shutdown()
            sessionSide.shutdown()
        }
    }
}

/// How a test asks `openrun attach` to end.
enum EndingRequest: Sendable, CustomTestStringConvertible {
    case detachKey
    case terminateSignal

    var exitCode: Int32 {
        switch self {
        case .detachKey: 0
        case .terminateSignal: 128 + SIGTERM
        }
    }

    var testDescription: String {
        switch self {
        case .detachKey: "Control-]"
        case .terminateSignal: "SIGTERM"
        }
    }
}

/// The number of keys that a stand-in session has received.
private final class ReceivedKeyCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var total: Int { lock.withLock { count } }

    func add(_ keys: Int) {
        lock.withLock { count += keys }
    }
}
