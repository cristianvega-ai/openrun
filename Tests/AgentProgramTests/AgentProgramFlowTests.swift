import AgentProgram
import Darwin
import Foundation
import PseudoTerminal
import Testing

/// A side that falls behind makes the other side wait, and no memory grows
/// without a limit.
@Suite struct AgentProgramFlowTests {
    @Test func aFloodWaitsForTheReaderAndThenComesWhole() async throws {
        let byteCount = 50_000_000
        let program = try startProgram("head", ["-c", "\(byteCount)", "/dev/zero"])
        // Nobody reads, so the program waits in its own write.
        try await Task.sleep(for: .milliseconds(500))
        #expect(runs(program.processIdentifier))
        let bytes = await readAll(program)
        #expect(bytes.count == byteCount)
        #expect(await program.waitForExit() == .exited(status: 0))
    }
}
