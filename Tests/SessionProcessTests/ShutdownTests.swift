import Darwin
import Foundation
import SessionProcessHarness
import SessionProtocol
import Synchronization
import Testing


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

        @Test func theSocketIsPrivateInsideAPrivateFolder() async throws {
            let process = try RunningSessionProcess(socketRelativePath: "private/socket")
            defer { process.stop() }
            let folderMode = try FileManager.default.attributesOfItem(atPath: process.directory.appendingPathComponent("private").path)[.posixPermissions] as? Int
            let socketMode = try FileManager.default.attributesOfItem(atPath: process.socketPath)[.posixPermissions] as? Int
            #expect(folderMode == 0o700)
            #expect(socketMode == 0o600)
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
