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

    @Test func theProgramSeesTheGivenSize() async throws {
        let result = try await run(shell("stty size", size: PseudoTerminalSize(columns: 100, rows: 30)))
        #expect(lines(result.text) == ["30 100"])
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
}
