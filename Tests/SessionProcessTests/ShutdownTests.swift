import Darwin
import Foundation
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing

/// Runs `body` and shuts the connection down when it takes longer than
/// `limit`, so a regression fails the test instead of hanging `swift test`.
private func withTimeLimit<Result>(_ limit: TimeInterval, on connection: MessageConnection, _ body: () throws -> Result) rethrows -> (result: Result, timedOut: Bool) {
    let didTimeOut = Mutex(false)
    let watchdog = DispatchWorkItem {
        didTimeOut.withLock { $0 = true }
        connection.shutdown()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: watchdog)
    defer { watchdog.cancel() }
    let result = try body()
    return (result, didTimeOut.withLock { $0 })
}

private func processExists(_ identifier: pid_t) -> Bool {
    kill(identifier, 0) == 0 || errno != ESRCH
}

/// Starts a session whose program prints its own process identifier, then waits.
private func startSleepingSession(_ process: RunningSessionProcess, script: String = "echo process=$$; exec sleep 300") async throws -> pid_t {
    let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
    #expect(await process.waitForScreen(of: identifier, containing: "process="))
    let text = try process.screenText(of: identifier)
    let digits = text.split(separator: "\n").first { $0.hasPrefix("process=") }.map { $0.dropFirst(8) }
    return try #require(digits.flatMap { pid_t($0) })
}

/// A session whose program leads its terminal session with a child in a
/// process group of its own and a child that ignores SIGHUP. Before the repair,
/// kill and shutdown signalled only the program's group, and sent no SIGKILL
/// once the program had ended, so both children lived on.
struct SessionProgramFamily {
    static let program = ["/usr/bin/perl", "-e", #"""
        $| = 1;
        my $grouped = fork();
        if ($grouped == 0) { setpgrp(0, 0); print "grouped-ready\n"; sleep 300; exit 0; }
        my $ignoring = fork();
        if ($ignoring == 0) { $SIG{HUP} = "IGNORE"; print "ignoring-ready\n"; sleep 300; exit 0; }
        print "leader=$$ grouped=$grouped ignoring=$ignoring\n";
        sleep 300;
        """#]

    let identifier: String
    let leader: pid_t
    let grouped: pid_t
    let ignoring: pid_t

    var all: [pid_t] { [leader, grouped, ignoring] }

    /// Starts the session and waits until both children are set up.
    static func start(in process: RunningSessionProcess) async throws -> SessionProgramFamily {
        let identifier = try process.createSession(program: program)
        for marker in ["grouped-ready", "ignoring-ready", "leader="] {
            #expect(await process.waitForScreen(of: identifier, containing: marker), "no \(marker) on the screen")
        }
        let text = try process.screenText(of: identifier)
        func number(after label: String) -> pid_t? {
            guard let range = text.range(of: label) else { return nil }
            return pid_t(text[range.upperBound...].prefix { $0.isNumber })
        }
        let family = SessionProgramFamily(
            identifier: identifier,
            leader: try #require(number(after: "leader=")),
            grouped: try #require(number(after: "grouped=")),
            ignoring: try #require(number(after: "ignoring="))
        )
        #expect(getsid(family.grouped) == family.leader && getpgid(family.grouped) == family.grouped)
        #expect(getsid(family.ignoring) == family.leader && getpgid(family.ignoring) == family.leader)
        return family
    }

    /// `getsid` fails for a process that is gone and for a zombie. A number
    /// that went to another program reports another session.
    func isInSession(_ processIdentifier: pid_t) -> Bool {
        getsid(processIdentifier) == leader
    }

    /// The processes still in the session once `limit` has passed, or as soon
    /// as none is left.
    func survivors(within limit: Duration) async -> [pid_t] {
        _ = await eventually(timeout: limit) { !all.contains(where: isInSession) }
        return all.filter(isInSession)
    }

    /// A process that survived a failed test must not outlive the test run.
    func killSurvivors() {
        for processIdentifier in all where isInSession(processIdentifier) {
            kill(processIdentifier, SIGKILL)
        }
    }
}

extension SessionProcessIntegration {
    @Suite struct ShutdownTests {
        /// Shutdown signalled only the program's process group, so both children lived on.
        @Test func shutdownEndsEveryProcessOfTheTerminalSession() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let family = try await SessionProgramFamily.start(in: process)
            defer { family.killSurvivors() }

            process.send(signal: SIGTERM)
            #expect(await process.waitForExit(timeout: 10) == 0)
            let survivors = await family.survivors(within: .seconds(5))
            #expect(survivors.isEmpty, "still in the session of \(family.leader): \(survivors)")
        }

        @Test(arguments: [SIGTERM, SIGINT, SIGHUP])
        func aStopSignalEndsEveryProgramAndRemovesTheSocket(signal: Int32) async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let first = try await startSleepingSession(process)
            let second = try await startSleepingSession(process)
            #expect(processExists(first) && processExists(second))
            #expect(FileManager.default.fileExists(atPath: process.socketPath))

            process.send(signal: signal)
            #expect(await process.waitForExit() == 0)

            #expect(!FileManager.default.fileExists(atPath: process.socketPath))
            #expect(await eventually(timeout: .seconds(5)) { !processExists(first) && !processExists(second) })
            #expect(process.log.contains("Stopped."))
        }

        @Test func aProgramThatIgnoresHangUpIsKilledAfterAShortWait() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let child = try await startSleepingSession(process, script: "trap '' HUP; echo process=$$; while true; do sleep 1; done")
            process.send(signal: SIGTERM)
            #expect(await process.waitForExit(timeout: 10) == 0)
            #expect(await eventually(timeout: .seconds(5)) { !processExists(child) })
        }

        @Test func aClientThatIsAlreadyConnectedCannotStartASessionOnceShutdownHasBegun() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            // This program ignores SIGHUP, so the session process waits for it
            // while the registry is shutting down. It writes a file for each
            // SIGHUP it gets. The registry sets its stopping flag before it
            // sends the first SIGHUP, so the file shows that the flag is set.
            // The socket file goes before that, so it shows nothing.
            let hangUpFile = process.directory.appendingPathComponent("hang-up-received")
            let first = try await startSleepingSession(
                process,
                script: "trap 'echo hang-up > \"\(hangUpFile.path)\"' HUP; echo process=$$; while true; do sleep 0.05; done"
            )
            let markerFile = process.directory.appendingPathComponent("late-program-process")
            defer {
                // A program that survived must not outlive the test.
                if let text = try? String(contentsOf: markerFile, encoding: .utf8), let survivor = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    kill(survivor, SIGKILL)
                }
            }

            let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
            defer { connection.shutdown() }
            try connection.greetSessionProcess()

            process.send(signal: SIGTERM)
            #expect(await eventually { FileManager.default.fileExists(atPath: hangUpFile.path) }, "the program never got SIGHUP")
            #expect(!FileManager.default.fileExists(atPath: process.socketPath))
            // The registry waits one second for a program that ignores SIGHUP.
            #expect(processExists(first))

            try connection.send(ClientMessage.createSession(
                folder: process.directory.path,
                command: ["/bin/sh", "-c", "echo $$ > '\(markerFile.path)'; exec sleep 300"],
                size: SessionSize(columns: 80, rows: 24),
                environment: ["PATH": "/usr/bin:/bin"]
            ))
            let answer = try withTimeLimit(30, on: connection) { try connection.receive(ServerMessage.self) }
            guard case .failure(let failure)? = answer.result else {
                Issue.record("The session process started a session during shutdown, or closed the connection first: \(String(describing: answer.result)), timed out: \(answer.timedOut).")
                return
            }
            #expect(failure.reason == .launchFailed)
            #expect(failure.message == "The session process is stopping.")

            #expect(await process.waitForExit(timeout: 10) == 0)
            #expect(await eventually(timeout: .seconds(5)) { !processExists(first) })
            // The refused program never ran.
            #expect(!FileManager.default.fileExists(atPath: markerFile.path))
        }

        /// The server dies while a client is attached. The tool must
        /// end with the exact status of the program, and leave the terminal in
        /// the mode it found.
        @Test func aClientAttachedAtShutdownEndsWithTheStatusOfTheProgramAndRestoresTheTerminal() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let identifier = try process.createSession(program: ["/bin/sh", "-c", "echo session-is-up; exec sleep 300"])
            #expect(await process.waitForScreen(of: identifier, containing: "session-is-up"))
            let executable = RunningSessionProcess.commandExecutable.path
            let script = """
                saved=$(stty -g)
                echo before-attach
                '\(executable)' attach \(identifier) --socket '\(process.socketPath)'
                code=$?
                echo "status=$code"
                if [ "$(stty -g)" = "$saved" ]; then echo mode-restored; else echo mode-changed; fi
                """
            let attached = try AttachedTerminal(shellScript: script, folder: process.directory)
            defer { attached.closeNow() }
            #expect(await attached.waitForScreen(containing: "session-is-up"))
            #expect(await eventually { attached.isInRawMode })

            process.send(signal: SIGTERM)
            // sleep ends by SIGHUP, signal 1, so the status is 128 + 1.
            #expect(await attached.waitForScreen(containing: "mode-"), "screen: \(attached.screenText)")
            let screen = attached.screenText
            #expect(screen.contains("status=129"), "screen: \(screen)")
            #expect(screen.contains("mode-restored") && !screen.contains("mode-changed"), "screen: \(screen)")
            #expect(!attached.isInRawMode)
            #expect(await attached.waitForExit() == .exited(status: 0))
            #expect(await process.waitForExit() == 0)
        }

        /// Shutdown closed every client at once, so the output and the
        /// exit status that still waited for a slow client were lost.
        ///
        /// The client reads nothing and the program writes 1.5 MiB. That is more
        /// than the session process holds in its buffers and the socket, so
        /// output still waits for the client when shutdown starts. (`openrun
        /// attach` reads up to 1 MiB ahead, so a smaller amount never waits.)
        @Test func aPausedAttachedClientStillGetsTheExitStatusAtShutdown() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let goFile = process.directory.appendingPathComponent("go")
            let script = "while [ ! -e '\(goFile.path)' ]; do sleep 0.05; done; "
                + "dd if=/dev/zero bs=65536 count=24 2>/dev/null | tr '\\0' 'z'; echo; echo printed-everything; exec sleep 300"
            let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
            let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
            defer { connection.close() }
            try connection.greetSessionProcess()
            try connection.send(ClientMessage.attach(identifier: try #require(UUID(uuidString: identifier)), size: SessionSize(columns: 80, rows: 24)))
            let answer = try withTimeLimit(30, on: connection) { try connection.receive(ServerMessage.self) }
            guard case .attached = answer.result else {
                Issue.record("the attach was answered with \(String(describing: answer.result))")
                return
            }

            // From here on the client reads nothing, so the output waits in the
            // session process.
            FileManager.default.createFile(atPath: goFile.path, contents: Data())
            #expect(await process.waitForScreen(of: identifier, containing: "printed-everything"))

            process.send(signal: SIGTERM)
            try await Task.sleep(for: .milliseconds(800))

            var exit: SessionExit?
            let reading = try withTimeLimit(30, on: connection) {
                while let message = try connection.receive(ServerMessage.self) {
                    if case .exited(let how) = message {
                        exit = how
                        break
                    }
                }
            }
            #expect(!reading.timedOut, "the connection stayed open without an exit status")
            // sleep ends by SIGHUP, signal 1.
            #expect(exit == .signaled(signal: SIGHUP), "exit status: \(String(describing: exit))")
            #expect(await process.waitForExit() == 0)
        }

        /// When the wait for the socket failed, the caller got no
        /// object to stop, and the session process ran on for the rest of the
        /// test run.
        @Test func aHarnessStartThatFailsStopsTheProcessItStarted() async throws {
            let started = Mutex<pid_t>(0)
            // A wait of no time at all fails while the process still runs.
            #expect(throws: HarnessError.self) {
                _ = try RunningSessionProcess(readyTimeout: 0) { identifier in started.withLock { $0 = identifier } }
            }
            let identifier = started.withLock { $0 }
            #expect(identifier > 0, "the process did not start")
            if identifier > 0 {
                let ended = await eventually(timeout: .seconds(10)) { !processExists(identifier) }
                #expect(ended, "process \(identifier) still runs")
                // A process that is still there must not outlive the run.
                if !ended { kill(identifier, SIGKILL) }
            }
        }

        @Test func aStaleSocketFileIsReplaced() async throws {
            let first = try RunningSessionProcess()
            defer { first.stop() }
            first.send(signal: SIGKILL)
            #expect(await first.waitForExit() != nil)
            // SIGKILL gives the process no time to remove its socket file.
            #expect(FileManager.default.fileExists(atPath: first.socketPath))

            let second = try RunningSessionProcess(directory: first.directory, logName: "second-log")
            defer { second.stop() }
            #expect(try second.listedIdentifiers().isEmpty)
        }

        @Test func theSocketIsPrivateInsideAPrivateFolder() async throws {
            let process = try RunningSessionProcess(socketRelativePath: "private/socket")
            defer { process.stop() }
            let folderMode = try FileManager.default.attributesOfItem(atPath: process.directory.appendingPathComponent("private").path)[.posixPermissions] as? Int
            let socketMode = try FileManager.default.attributesOfItem(atPath: process.socketPath)[.posixPermissions] as? Int
            #expect(folderMode == 0o700)
            #expect(socketMode == 0o600)
        }

        @Test func aFileThatIsNotASocketIsLeftAlone() async throws {
            let directory = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.appendingPathComponent("socket")
            try Data("precious".utf8).write(to: path)
            let process = try RunningSessionProcess(directory: directory, waitUntilReady: false)
            defer { process.stop() }
            #expect(await process.waitForExit() == 1)
            #expect(process.log.contains("not a socket"))
            #expect(try String(contentsOf: path, encoding: .utf8) == "precious")
        }

        @Test func aSocketPathThatIsTooLongGetsAClearError() throws {
            let directory = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let longPath = "/" + String(repeating: "x", count: 200)

            let session = Process()
            session.executableURL = RunningSessionProcess.sessionExecutable
            session.arguments = ["--socket", longPath]
            let errorPipe = Pipe()
            session.standardError = errorPipe
            try session.run()
            session.waitUntilExit()
            let sessionError = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            #expect(session.terminationStatus == 1)
            #expect(sessionError.contains("too long"))

            let tool = try RunningSessionProcess.runOpenrun(["list", "--socket", longPath], in: directory)
            #expect(tool.status == 1)
            #expect(tool.standardError.contains("too long"))
        }
    }
}
