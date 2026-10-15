import CryptoKit
import Darwin
import Foundation
import Synchronization
import Testing
@testable import PseudoTerminal

/// Runs a program to its end and returns everything it printed and how it ended.
private func run(_ launch: ProgramLaunch, input: String? = nil) async throws -> (text: String, exit: ProgramExit) {
    let terminal = try PseudoTerminal(launching: launch)
    if let input { terminal.write(Array(input.utf8)) }
    var collected: [UInt8] = []
    for await chunk in terminal.output { collected += chunk }
    let exit = await terminal.waitForExit()
    return (String(decoding: collected, as: UTF8.self), exit)
}

private func shell(_ script: String, folder: String = "/", size: PseudoTerminalSize = PseudoTerminalSize(columns: 80, rows: 24)) -> ProgramLaunch {
    ProgramLaunch(
        executablePath: "/bin/sh",
        argumentZero: "sh",
        arguments: ["-c", script],
        folder: folder,
        environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
        size: size
    )
}

/// Reads output until it contains `marker`, and returns the bytes read so far.
/// The caller can go on reading the same stream afterwards.
private func waitForText(_ marker: String, in terminal: PseudoTerminal) async -> [UInt8] {
    var collected: [UInt8] = []
    for await chunk in terminal.output {
        collected += chunk
        if String(decoding: collected, as: UTF8.self).contains(marker) { break }
    }
    return collected
}

/// Collects the output of a program in the background, so a test can wait
/// for it with a time limit and end the program when the limit passes.
final class OutputCollector: Sendable {
    private let collected = Mutex<[UInt8]>([])

    init(reading terminal: PseudoTerminal) {
        Task { [self] in
            for await chunk in terminal.output {
                collected.withLock { $0 += chunk }
            }
        }
    }

    var text: String {
        collected.withLock { String(decoding: $0, as: UTF8.self) }
    }

    /// Waits until the output contains `marker`, for at most `timeout`.
    func waitFor(_ marker: String, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !text.contains(marker) {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }
}

/// Letters and digits in a fixed order, so that a lost or moved piece changes
/// the checksum.
func patternBytes(count: Int) -> [UInt8] {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789".utf8)
    var bytes = [UInt8](repeating: 0, count: count)
    var state: UInt32 = 12345
    for index in 0..<count {
        state = state &* 1_103_515_245 &+ 12345
        bytes[index] = alphabet[Int((state >> 16) % UInt32(alphabet.count))]
    }
    return bytes
}

/// Polls until the condition holds, for at most five seconds.
func eventuallyTrue(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

func checksum(_ bytes: [UInt8]) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

func lines(_ text: String) -> [String] {
    text.split(whereSeparator: \.isNewline).map(String.init)
}

@Suite struct PseudoTerminalTests {
    @Test func collectsOutputAndTheExitStatus() async throws {
        let result = try await run(shell("echo hello; exit 3"))
        #expect(lines(result.text) == ["hello"])
        #expect(result.exit == .exited(status: 3))
    }

    @Test func reportsASignalThatEndedTheProgram() async throws {
        let result = try await run(shell("kill -KILL $$"))
        #expect(result.exit == .signaled(signal: SIGKILL))
        #expect(result.exit.shellStatus == 128 + SIGKILL)
    }

    @Test func theProgramIsASessionLeaderWithAControllingTerminal() async throws {
        let terminal = try PseudoTerminal(launching: shell("test -r /dev/tty && echo controlling; sleep 30"))
        let output = OutputCollector(reading: terminal)
        defer { Task { await terminal.terminate() } }
        // The program runs, so the child has done its set-up.
        #expect(await output.waitFor("controlling", timeout: .seconds(10)), "output: \(output.text)")
        let program = terminal.processIdentifier
        // Leading a process group is not enough: a program that only called
        // setpgid would lead its group but stay in the session of its parent.
        // A session leader names the session after itself.
        #expect(getsid(program) == program, "the session is \(getsid(program)), the program is \(program)")
        #expect(getpgid(program) == program)
        #expect(getsid(program) != getsid(0), "the program shares the session of the test")
    }

    @Test func theTerminalPathIsTheControllingTerminalOfTheProgram() async throws {
        // ps reads the controlling terminal from the process. A program that
        // only had the device as standard input would show "??" here.
        let terminal = try PseudoTerminal(launching: shell("ps -o tty= -p $$; tty"))
        var collected: [UInt8] = []
        for await chunk in terminal.output { collected += chunk }
        let reported = lines(String(decoding: collected, as: UTF8.self))
        #expect(reported.first.map { "/dev/" + $0.trimmingCharacters(in: .whitespaces) } == terminal.terminalPath)
        #expect(reported.last == terminal.terminalPath)
    }

    @Test func aProgramThatIsNotAShellHasTheControllingTerminalToo() async throws {
        // sleep never opens the terminal itself. Only the launch can give it
        // a controlling terminal, so ps, run from outside, shows the device.
        var launch = shell("")
        launch.executablePath = "/bin/sleep"
        launch.argumentZero = "sleep"
        launch.arguments = ["30"]
        let terminal = try PseudoTerminal(launching: launch)
        let status = Process()
        status.executableURL = URL(fileURLWithPath: "/bin/ps")
        status.arguments = ["-o", "tty=", "-p", String(terminal.processIdentifier)]
        let pipe = Pipe()
        status.standardOutput = pipe
        try status.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        status.waitUntilExit()
        await terminal.terminate()
        let reported = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect("/dev/" + reported == terminal.terminalPath)
    }

    @Test func theProgramSeesTheGivenSize() async throws {
        let result = try await run(shell("stty size", size: PseudoTerminalSize(columns: 100, rows: 30)))
        #expect(lines(result.text) == ["30 100"])
    }

    @Test func resizeChangesTheSizeTheProgramReads() async throws {
        let launch = shell("read line; stty size")
        let terminal = try PseudoTerminal(launching: launch)
        try terminal.resize(to: PseudoTerminalSize(columns: 120, rows: 40))
        terminal.write(Array("go\n".utf8))
        var collected: [UInt8] = []
        for await chunk in terminal.output { collected += chunk }
        #expect(lines(String(decoding: collected, as: UTF8.self)).last == "40 120")
    }

    @Test func theProgramGetsExactlyTheGivenEnvironment() async throws {
        // Run env itself, because a shell adds variables of its own.
        var launch = shell("")
        launch.executablePath = "/usr/bin/env"
        launch.arguments = []
        launch.environment = ["ALPHA": "one", "BETA": "two words"]
        let result = try await run(launch)
        #expect(Set(lines(result.text)) == ["ALPHA=one", "BETA=two words"])
    }

    @Test func theProgramStartsInTheGivenFolder() async throws {
        // The shell prints the real path, with symbolic links resolved.
        let folder = String(cString: realpath(NSTemporaryDirectory(), nil))
        let result = try await run(shell("pwd", folder: folder))
        #expect(lines(result.text) == [folder])
    }

    @Test func theTerminalPathNamesTheDeviceOfTheProgram() async throws {
        let terminal = try PseudoTerminal(launching: shell("tty"))
        var collected: [UInt8] = []
        for await chunk in terminal.output { collected += chunk }
        #expect(lines(String(decoding: collected, as: UTF8.self)) == [terminal.terminalPath])
        #expect(terminal.terminalPath.hasPrefix("/dev/tty"))
    }

    @Test func inputReachesTheProgram() async throws {
        let result = try await run(shell("read word; echo got-$word"), input: "typed\n")
        #expect(lines(result.text).contains("got-typed"))
    }

    @Test func largeInputReachesAProgramThatReadsSlowly() async throws {
        // 100 thousand bytes is far more than the kernel buffers, so the
        // write must wait without blocking the caller.
        let count = 100_000
        let terminal = try PseudoTerminal(launching: shell("stty raw -echo; echo ready; sleep 0.3; head -c \(count) | wc -c"))
        var collected = await waitForText("ready", in: terminal)
        terminal.write(Array(repeating: UInt8(ascii: "x"), count: count))
        for await chunk in terminal.output { collected += chunk }
        let text = String(decoding: collected, as: UTF8.self)
        #expect(lines(text).last?.trimmingCharacters(in: .whitespaces) == "\(count)")
    }

    @Test func inputPastTheBacklogLimitWaitsAndArrivesCompleteAndInOrder() async throws {
        // 12 MiB is more than the 8 MiB backlog. The program reads nothing for
        // a second, so the later writes must wait for room instead of being lost.
        let total = 12 * 1024 * 1024
        let input = patternBytes(count: total)
        let terminal = try PseudoTerminal(launching: shell("stty raw -echo; echo ready; sleep 1; head -c \(total) | shasum -a 256; sleep 60"))
        let output = OutputCollector(reading: terminal)
        #expect(await output.waitFor("ready", timeout: .seconds(10)))

        let start = ContinuousClock.now
        for offset in stride(from: 0, to: total, by: 256 * 1024) {
            try await terminal.type(Array(input[offset..<offset + 256 * 1024]))
        }
        // The last writes waited until the program began to read.
        #expect(ContinuousClock.now - start > .milliseconds(500))
        let arrived = await output.waitFor(checksum(input), timeout: .seconds(30))
        await terminal.terminate()
        #expect(arrived, "output: \(output.text)")
    }

    @Test func typedInputThatWaitsFailsWhenTheProgramEnds() async throws {
        let piece = patternBytes(count: 1024 * 1024)
        let terminal = try PseudoTerminal(launching: shell("stty raw -echo; echo ready; sleep 2"))
        let output = OutputCollector(reading: terminal)
        #expect(await output.waitFor("ready", timeout: .seconds(10)))
        // The program never reads. This fills the backlog.
        for _ in 0..<8 {
            try await terminal.type(piece)
        }
        // This write waits for room until the program ends.
        await #expect(throws: PseudoTerminalError.self) {
            try await terminal.type(patternBytes(count: 64 * 1024))
        }
        _ = await terminal.waitForExit()
        // A write after the end fails at once.
        await #expect(throws: PseudoTerminalError.self) {
            try await terminal.type(Array("late".utf8))
        }
    }

    @Test func answersNeverWaitButHoldTheOutputReaderPastTheirLimit() async throws {
        let total = 2 * 1024 * 1024
        let terminal = try PseudoTerminal(launching: shell("stty raw -echo; echo ready; sleep 1.5; head -c \(total) > /dev/null; echo drained; sleep 60"))
        let output = OutputCollector(reading: terminal)
        #expect(await output.waitFor("ready", timeout: .seconds(10)))

        // Answers go into the backlog at once, past the limit of typed input.
        for _ in 0..<(total / (64 * 1024)) {
            terminal.write(patternBytes(count: 64 * 1024))
        }
        // More answers wait than their limit, so the reader of the output must
        // wait until the program reads them.
        let start = ContinuousClock.now
        await terminal.waitForAnswerRoom()
        #expect(ContinuousClock.now - start > .milliseconds(500))
        #expect(await output.waitFor("drained", timeout: .seconds(20)))
        await terminal.terminate()
    }

    @Test func noOtherDescriptorLeaksIntoTheProgram() async throws {
        // Descriptors that the test process holds open and does not mark
        // close-on-exec, low and high, so the child must close them itself.
        // The soft limit is raised for the test, because the child closes
        // only up to that number.
        var limits = rlimit()
        #expect(getrlimit(RLIMIT_NOFILE, &limits) == 0)
        let original = limits
        limits.rlim_cur = max(limits.rlim_cur, min(limits.rlim_max, 4096))
        #expect(setrlimit(RLIMIT_NOFILE, &limits) == 0)
        defer {
            var restored = original
            setrlimit(RLIMIT_NOFILE, &restored)
        }
        let lowest = open("/dev/null", O_RDONLY)
        #expect(lowest >= 3)
        var sentinels = [lowest]
        for minimum in [40, 300, 3000] {
            sentinels.append(fcntl(lowest, F_DUPFD, Int32(minimum)))
        }
        defer { sentinels.filter { $0 >= 0 }.forEach { close($0) } }
        for sentinel in sentinels {
            // A sentinel that did not open, or that closes on exec, would
            // let a leak pass unseen.
            #expect(sentinel >= 3)
            #expect(fcntl(sentinel, F_GETFD) >= 0 && fcntl(sentinel, F_GETFD) & FD_CLOEXEC == 0, "descriptor \(sentinel) is not usable as a sentinel")
        }

        // The program lists every descriptor from 3 up to 4095 that it holds.
        // The first line opens 7 on purpose, so a program that sees nothing,
        // because the scan itself is wrong, fails the test.
        let scan = #"/usr/bin/perl -MPOSIX -e 'for my $number (3 .. 4095) { print "open-$number\n" if defined POSIX::dup($number) }'"#
        let result = try await run(shell("exec 7</dev/null; \(scan); echo done"))
        #expect(lines(result.text) == ["open-7", "done"], "the program saw: \(lines(result.text))")
    }

    @Test func masterDescriptorClosesAfterTheProgramEnds() async throws {
        let terminal = try PseudoTerminal(launching: shell("echo done"))
        #expect(terminal.masterDescriptorForTesting >= 0)
        for await _ in terminal.output {}
        _ = await terminal.waitForExit()
        // The sources close the descriptor asynchronously after the exit.
        for _ in 0..<100 where terminal.masterDescriptorForTesting >= 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(terminal.masterDescriptorForTesting == -1)
    }

    /// When waitpid failed, the program was reported as ended
    /// with status 0, a success that nobody saw.
    @Test func aProgramThatAnotherWaiterReapedIsNotReportedAsASuccess() async throws {
        let terminal = try PseudoTerminal(launching: shell("sleep 0.3; exit 3"))
        let processIdentifier = terminal.processIdentifier
        // Another waiter reaps the program first, so the waitpid of the pseudo
        // terminal fails. When the pseudo terminal wins instead, it sees the
        // real status, which is not a success either.
        let reaped = await withCheckedContinuation { (continuation: CheckedContinuation<pid_t, Never>) in
            Thread {
                var status: Int32 = 0
                continuation.resume(returning: waitpid(processIdentifier, &status, 0))
            }.start()
        }
        let exit = await terminal.waitForExit()
        print("reaped-elsewhere: the test's waitpid returned \(reaped); the pseudo terminal reported \(exit)")
        #expect(exit != .exited(status: 0))
    }

    @Test func terminateEndsAProgramWithHangUp() async throws {
        let terminal = try PseudoTerminal(launching: shell("sleep 60"))
        await terminal.terminate()
        let exit = await terminal.waitForExit()
        #expect(exit == .signaled(signal: SIGHUP))
    }

    @Test func terminateKillsAProgramThatIgnoresHangUp() async throws {
        let terminal = try PseudoTerminal(launching: shell("trap '' HUP; echo ready; while true; do sleep 1; done"))
        // The shell must have installed its trap before the hang-up arrives.
        _ = await waitForText("ready", in: terminal)
        await terminal.terminate(gracePeriod: .milliseconds(200))
        let exit = await terminal.waitForExit()
        #expect(exit == .signaled(signal: SIGKILL))
    }

    @Test func terminateAfterTheExitDoesNothing() async throws {
        let terminal = try PseudoTerminal(launching: shell("exit 0"))
        _ = await terminal.waitForExit()
        await terminal.terminate()
        #expect(await terminal.waitForExit() == .exited(status: 0))
    }

    @Test func aMissingProgramFailsToLaunch() {
        var launch = shell("")
        launch.executablePath = "no-such-program-here"
        #expect(throws: PseudoTerminalError.self) { _ = try PseudoTerminal(launching: launch) }
    }

    @Test func aMissingFolderFailsToLaunch() {
        #expect(throws: PseudoTerminalError.self) {
            _ = try PseudoTerminal(launching: shell("true", folder: "/no/such/folder"))
        }
    }

    @Test func aBareNameIsFoundInTheLaunchPath() async throws {
        var launch = shell("")
        launch.executablePath = "echo"
        launch.arguments = ["found"]
        let result = try await run(launch)
        #expect(lines(result.text) == ["found"])
    }
}
