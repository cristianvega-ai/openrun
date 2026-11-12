import Foundation
import SessionConnection
import SessionProcessHarness
import SessionProtocol
import Testing

/// Command-K, through the socket of a real session process.
@Suite struct ClearScrollbackTests {
    /// The lines of the screen and the scrollback of a session.
    private func lines(of identifier: String, in process: RunningSessionProcess) throws -> [String] {
        try process.runCommand(["read", identifier, "--scrollback"]).outputLines
    }

    /// Attaches, sends Command-K, and leaves.
    private func clear(_ identifier: String, in process: RunningSessionProcess) throws {
        let client = try SessionClient(location: try SocketLocation(path: process.socketPath))
        let session = try #require(UUID(uuidString: identifier))
        let attachment = try client.attach(to: session, size: SessionSize(columns: 80, rows: 24), relaysRawOutput: false, receivesSizeChanges: false)
        attachment.startReceiving { _ in }
        try attachment.clearScrollback()
        try attachment.detach()
    }

    @Test func aShellAtItsPromptLosesItsScrollbackAndItsScreenAndDrawsItsPromptAgain() async throws {
        try await RunningSessionProcess.run { process in
            // zsh with no start files: its line editor turns on bracketed paste, as the shell of a user does.
            let identifier = try process.createSession(program: ["/bin/zsh", "-f", "-i"], environment: ["PS1": "test> ", "PATH": "/usr/bin:/bin"])
            #expect(await eventually { (try? lines(of: identifier, in: process).last?.hasPrefix("test>")) == true })
            _ = try process.runCommand(["send", identifier, "--enter", "seq 1 100"])
            #expect(await eventually { (try? lines(of: identifier, in: process).contains("100")) == true })
            try clear(identifier, in: process)
            #expect(await eventually { (try? lines(of: identifier, in: process).map { $0.trimmingCharacters(in: .whitespaces) }) == ["test>"] })
        }
    }

    @Test func aProgramThatIsNoShellKeepsItsScreenAndLosesItsScrollback() async throws {
        try await RunningSessionProcess.run { process in
            let identifier = try process.createSession(program: ["/bin/sh", "-c", "seq 1 100; exec sleep 60"])
            #expect(await eventually { (try? lines(of: identifier, in: process).count) ?? 0 >= 100 })
            try clear(identifier, in: process)
            #expect(await eventually { (try? lines(of: identifier, in: process).count) ?? 100 <= 24 })
            let kept = try lines(of: identifier, in: process)
            #expect(kept.last == "100" && !kept.contains("50"))
        }
    }
}
