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

    /// Forks a child that ignores SIGHUP, which forks a grandchild that moves
    /// to a group of its own and stops itself. The child reports once the
    /// grandchild has stopped.
    static let stoppedScript = #"""
        use POSIX ();
        $| = 1;
        my $ignoring = fork();
        if ($ignoring == 0) {
            $SIG{HUP} = "IGNORE";
            my $stopped = fork();
            if ($stopped == 0) { $SIG{HUP} = "DEFAULT"; setpgrp(0, 0); kill "STOP", $$; sleep 300; exit 0; }
            waitpid($stopped, POSIX::WUNTRACED());
            print "stopped=$stopped\n";
            print "ignoring-ready\n";
            sleep 300; exit 0;
        }
        print "leader=$$ grouped=0 ignoring=$ignoring\n";
        sleep 300;
        """#

    /// The script above, but the stopped grandchild catches SIGHUP and writes
    /// a marker file. A caught signal stays pending while the process is
    /// stopped, so the handler runs only after a SIGCONT. A stopped process
    /// whose SIGHUP keeps its default action would end on this system without
    /// one, so it cannot show whether the SIGCONT was sent.
    static func stoppedScriptCatchingHangUp(markerPath: String) -> String {
        stoppedScript.replacingOccurrences(
            of: #"$SIG{HUP} = "DEFAULT";"#,
            with: #"$SIG{HUP} = sub { open(my $marker, ">", "\#(markerPath)"); print $marker "ran\n"; close $marker; exit 0 };"#
        )
    }

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

    static func isStopped(_ processIdentifier: pid_t) -> Bool {
        var information = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(processIdentifier, PROC_PIDTBSDINFO, 0, &information, size) == size
            && information.pbi_status == UInt32(SSTOP)
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

    /// A stopped process acts on SIGHUP only when it runs, so its group gets
    /// SIGCONT too. Its parent ignores SIGHUP and stays in the program's
    /// group, so the system itself does not continue the stopped group when
    /// the program ends.
    @Test func terminateContinuesAStoppedGroupSoItEndsOnTheHangUp() async throws {
        let marker = NSTemporaryDirectory() + "hangup-handler-\(UInt32.random(in: 0...UInt32.max))"
        defer { try? FileManager.default.removeItem(atPath: marker) }
        let script = SessionFamily.stoppedScriptCatchingHangUp(markerPath: marker)
        #expect(script != SessionFamily.stoppedScript, "the handler was not put into the script")
        let (terminal, family) = try await SessionFamily.start(script)
        defer { family.killSurvivors() }
        let stopped = try #require(family.stopped)
        #expect(await eventuallyTrue { SessionFamily.isStopped(stopped) }, "the child never stopped")

        let ending = Task { await terminal.terminate(gracePeriod: .seconds(4)) }
        // The parent of the stopped process ignores SIGHUP, so terminate would
        // wait the whole grace period. The stopped process must not wait for it.
        let start = ContinuousClock.now
        while family.isInSession(stopped), ContinuousClock.now - start < .seconds(2) {
            try await Task.sleep(for: .milliseconds(20))
        }
        let endedEarly = !family.isInSession(stopped)
        // Without the parent, the session has no process left, so terminate
        // returns before the grace period ends. A process that did not end
        // keeps the parent, because the system continues a stopped group
        // when the group loses its last parent outside the group.
        if endedEarly, family.isInSession(family.ignoring) { kill(family.ignoring, SIGKILL) }
        await ending.value
        #expect(endedEarly, "the stopped process waited for SIGKILL")
        // Only a continued process runs its handler, before any forced kill.
        #expect(FileManager.default.fileExists(atPath: marker), "the stopped process never ran its SIGHUP handler")
        let survivors = await family.survivors(after: .seconds(5))
        #expect(survivors.isEmpty, "still in the session: \(survivors)")
    }

    @Test func membersAreTheLiveProcessesOfTheSessionInEveryGroup() async throws {
        let (terminal, family) = try await SessionFamily.start(SessionFamily.stoppedScript)
        defer {
            family.killSurvivors()
            Task { await terminal.terminate(gracePeriod: .milliseconds(100)) }
        }
        let stopped = try #require(family.stopped)
        let leader = family.leader

        let members = try TerminalSessionProcesses(sessionIdentifier: leader).members()
        let byProcess = Dictionary(uniqueKeysWithValues: members.map { ($0.processIdentifier, $0) })
        #expect(byProcess[leader] == .init(processIdentifier: leader, groupIdentifier: leader, isStopped: false))
        #expect(byProcess[family.ignoring] == .init(processIdentifier: family.ignoring, groupIdentifier: leader, isStopped: false))
        #expect(byProcess[stopped] == .init(processIdentifier: stopped, groupIdentifier: stopped, isStopped: true))
        // The test process is in another session.
        #expect(byProcess[getpid()] == nil)
        #expect(members.allSatisfy { getsid($0.processIdentifier) == leader })
    }

    @Test func aProcessOutsideTheSessionIsNeverSignalled() async throws {
        let (terminal, family) = try await SessionFamily.start(SessionFamily.groupedAndIgnoringScript)
        defer {
            family.killSurvivors()
            Task { await terminal.terminate(gracePeriod: .milliseconds(100)) }
        }
        let session = TerminalSessionProcesses(sessionIdentifier: family.leader)

        // A process of the test's own session, listed as if it were a member,
        // as a process whose identifier went to another program would be. It
        // leads a group of its own, so a wrong signal reaches only itself.
        let outsider = Process()
        outsider.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        outsider.arguments = ["-e", "setpgrp(0, 0); sleep 30"]
        try outsider.run()
        defer {
            outsider.terminate()
            outsider.waitUntilExit()
        }
        let outsiderIdentifier = outsider.processIdentifier
        let deadline = ContinuousClock.now + .seconds(5)
        while getpgid(outsiderIdentifier) != outsiderIdentifier, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(getpgid(outsiderIdentifier) == outsiderIdentifier, "the outsider did not get a group of its own")
        let impostor = TerminalSessionProcesses.Member(
            processIdentifier: outsiderIdentifier,
            groupIdentifier: outsiderIdentifier,
            isStopped: false
        )
        #expect(session.send(SIGKILL, to: [impostor]) == 0)
        session.sendToEachGroup(SIGKILL, of: [impostor])
        try await Task.sleep(for: .milliseconds(200))
        #expect(outsider.isRunning)
    }

    @Test func aSessionWhoseProcessesEndedHasNoMembers() async throws {
        let (terminal, family) = try await SessionFamily.start(SessionFamily.groupedAndIgnoringScript)
        defer { family.killSurvivors() }
        let session = TerminalSessionProcesses(sessionIdentifier: family.leader)
        #expect(try session.members().count == 3)
        await terminal.terminate(gracePeriod: .milliseconds(200))
        #expect(try session.members().isEmpty)
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
        await terminal.terminate(gracePeriod: .milliseconds(300), session: session)
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
