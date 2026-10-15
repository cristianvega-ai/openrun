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

@Suite struct TerminalSessionProcessesTests {

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
