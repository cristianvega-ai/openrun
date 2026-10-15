import Darwin
import Foundation
import Testing
@testable import PseudoTerminal

/// A Perl script that runs as the program of a pseudo terminal.
private func scriptLaunch(_ script: String) -> ProgramLaunch {
    ProgramLaunch(
        executablePath: "/usr/bin/perl",
        argumentZero: "perl",
        arguments: ["-e", script],
        folder: "/",
        environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
        size: PseudoTerminalSize(columns: 200, rows: 24)
    )
}

/// The processes of a test program that leads its terminal session, as the
/// program reports them in its output.
private struct SessionFamily {
    /// Forks a child that moves to a process group of its own, and a child
    /// that ignores SIGHUP and stays in the program's group. Each child says
    /// when it is set up.
    static let groupedAndIgnoringScript = #"""
        $| = 1;
        my $grouped = fork();
        if ($grouped == 0) { setpgrp(0, 0); print "grouped-ready\n"; sleep 300; exit 0; }
        my $ignoring = fork();
        if ($ignoring == 0) { $SIG{HUP} = "IGNORE"; print "ignoring-ready\n"; sleep 300; exit 0; }
        print "leader=$$ grouped=$grouped ignoring=$ignoring\n";
        sleep 300;
        """#


    let leader: pid_t
    let grouped: pid_t
    let ignoring: pid_t
    let stopped: pid_t?

    var all: [pid_t] { [leader, grouped, ignoring, stopped ?? 0].filter { $0 > 0 } }

    /// Starts the script and waits until every child is set up.
    static func start(_ script: String) async throws -> (terminal: PseudoTerminal, family: SessionFamily) {
        let terminal = try PseudoTerminal(launching: scriptLaunch(script))
        let output = OutputCollector(reading: terminal)
        #expect(await output.waitFor("ignoring-ready", timeout: .seconds(10)), "output: \(output.text)")
        #expect(await output.waitFor("leader=", timeout: .seconds(10)), "output: \(output.text)")
        if !output.text.contains("grouped=0") {
            #expect(await output.waitFor("grouped-ready", timeout: .seconds(10)), "output: \(output.text)")
        }
        let text = output.text
        func number(after label: String) -> pid_t? {
            guard let range = text.range(of: label) else { return nil }
            return pid_t(text[range.upperBound...].prefix { $0.isNumber })
        }
        let family = SessionFamily(
            leader: try #require(number(after: "leader=")),
            grouped: try #require(number(after: "grouped=")),
            ignoring: try #require(number(after: "ignoring=")),
            stopped: number(after: "stopped=")
        )
        #expect(family.leader == terminal.processIdentifier)
        return (terminal, family)
    }

    /// `getsid` fails for a process that is gone and for a zombie. A number
    /// that went to another program reports another session.
    func isInSession(_ processIdentifier: pid_t) -> Bool {
        getsid(processIdentifier) == leader
    }

    /// The processes still in the session once `limit` has passed, or as soon
    /// as none is left.
    func survivors(after limit: Duration) async -> [pid_t] {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline, all.contains(where: isInSession) {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return all.filter(isInSession)
    }

    /// A process that survived a failed test must not outlive the test run.
    func killSurvivors() {
        for processIdentifier in all where isInSession(processIdentifier) {
            kill(processIdentifier, SIGCONT)
            kill(processIdentifier, SIGKILL)
        }
    }
}

@Suite struct TerminalSessionProcessesTests {
    /// Terminate signalled only the program's process group,
    /// and skipped SIGKILL once the program had ended. A child in a group of
    /// its own, and a child that ignores SIGHUP, lived on.
    @Test func terminateEndsEveryProcessOfTheTerminalSession() async throws {
        let (terminal, family) = try await SessionFamily.start(SessionFamily.groupedAndIgnoringScript)
        defer { family.killSurvivors() }
        #expect(getpgid(family.grouped) == family.grouped, "the child did not get a group of its own")
        #expect(getpgid(family.ignoring) == family.leader)

        await terminal.terminate(gracePeriod: .milliseconds(300))
        #expect(await terminal.waitForExit() == .signaled(signal: SIGHUP))
        let survivors = await family.survivors(after: .seconds(5))
        #expect(survivors.isEmpty, "still in the session: \(survivors)")
    }

    /// A failed process list is unknown, not empty.
    @Test func aFailedProcessListIsReportedNotTakenForAnEmptySession() throws {
        var session = TerminalSessionProcesses(sessionIdentifier: getpid())
        session.listProcessIdentifiers = { nil }
        #expect(throws: TerminalSessionProcesses.ListingFailed.self) { try session.members() }
        session.listProcessIdentifiers = { [] }
        #expect(try session.members().isEmpty)
    }

    /// With no process list, terminate still hangs up
    /// the program's group, as the fallback.
    @Test func terminateHangsUpTheProgramGroupWhenTheProcessListFails() async throws {
        let terminal = try PseudoTerminal(launching: scriptLaunch("sleep 300;"))
        var session = TerminalSessionProcesses(sessionIdentifier: terminal.processIdentifier)
        session.listProcessIdentifiers = { nil }
        await terminal.terminate(gracePeriod: .seconds(2), session: session)
        // With an empty list taken for the truth, nothing sent SIGHUP and
        // SIGKILL ended the program after the grace period.
        #expect(await terminal.waitForExit() == .signaled(signal: SIGHUP))
    }

    @Test func terminateKeepsSignallingUntilItsLimitsWhenTheProcessListFails() async throws {
        let terminal = try PseudoTerminal(launching: scriptLaunch(#"$| = 1; $SIG{HUP} = "IGNORE"; print "ready\n"; sleep 300;"#))
        // The program must ignore SIGHUP before terminate sends it.
        let output = OutputCollector(reading: terminal)
        #expect(await output.waitFor("ready", timeout: .seconds(10)), "output: \(output.text)")
        var session = TerminalSessionProcesses(sessionIdentifier: terminal.processIdentifier)
        session.listProcessIdentifiers = { nil }
        let start = ContinuousClock.now
        await terminal.terminate(gracePeriod: .milliseconds(500), session: session)
        #expect(await terminal.waitForExit() == .signaled(signal: SIGKILL))
        // The grace period passed first. The wait did not end at once.
        #expect(ContinuousClock.now - start >= .milliseconds(500))
    }
}
