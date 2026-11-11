import AgentProgram
import Darwin
import Testing

/// An object that nobody holds any more cannot leave its program behind.
@Suite struct AgentProgramReleaseTests {
    @Test func aDroppedProgramEndsItsGroupAndIsReaped() async throws {
        var program: AgentProgram? = try startProgram("sh", ["-c", "sh -c 'sleep 300 & echo $!; wait' & wait"])
        let leader = try #require(program?.processIdentifier)
        var text = ""
        for await chunk in try #require(program?.output) {
            text += String(decoding: chunk, as: UTF8.self)
            if text.hasSuffix("\n") { break }
        }
        let grandchild = try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        program = nil
        let deadline = ContinuousClock.now + .seconds(5)
        while kill(leader, 0) == 0 || runs(grandchild), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!runs(grandchild))
        // The leader was reaped, so not even its zombie is left.
        #expect(kill(leader, 0) == -1)
        if runs(grandchild) { killpg(leader, SIGKILL) }
    }
}
