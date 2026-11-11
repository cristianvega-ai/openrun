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

    @Test func aWriteWaitsForAProgramThatDoesNotReadAndFailsAtItsEnd() async throws {
        let program = try startProgram("sleep", ["300"])
        let writer = Task { try await program.write([UInt8](repeating: 65, count: 1_000_000)) }
        try await Task.sleep(for: .milliseconds(200))
        // A later write waits behind the first, and the caller's thread is free.
        let second = Task { try await program.write([66]) }
        await program.terminate()
        await #expect(throws: AgentProgramError.programEnded) { try await writer.value }
        await #expect(throws: AgentProgramError.programEnded) { try await second.value }
    }

    @Test func manyWritesReachAReaderInOrder() async throws {
        let program = try startProgram("cat")
        let reader = Task { await readAll(program) }
        var expected: [UInt8] = []
        for index in 0..<200 {
            let piece = [UInt8](repeating: UInt8(index % 256), count: 10_000)
            expected += piece
            try await program.write(piece)
        }
        program.closeInput()
        #expect(await reader.value == expected)
        #expect(await program.waitForExit() == .exited(status: 0))
    }
}
