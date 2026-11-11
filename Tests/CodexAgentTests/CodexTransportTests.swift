import AgentConversation
import AgentProgram
import Darwin
import Testing
@testable import CodexAgent

@Suite struct CodexTransportTests {
    @Test func aProgramThatEndsAtTheEndOfItsInputEndsByItself() async throws {
        let program = try AgentProgram(launching: AgentProgramLaunch(executablePath: "/bin/cat", folder: "/", environment: [:]))
        let transport: any CodexTransport = program
        try await transport.write(Array("line\n".utf8))
        await transport.end(gracePeriod: .seconds(10))
        let end = await transport.waitForEnd()
        #expect(end.exitStatus == 0)
        #expect(end.signal == nil)
    }

    @Test func aProgramThatReadsNothingIsMadeToEnd() async throws {
        let program = try AgentProgram(launching: AgentProgramLaunch(
            executablePath: "/bin/sleep", arguments: ["60"], folder: "/", environment: [:]))
        let start = ContinuousClock.now
        await program.end(gracePeriod: .milliseconds(100))
        #expect(await program.waitForEnd().signal == SIGTERM)
        #expect(ContinuousClock.now - start < .seconds(30))
    }
}
