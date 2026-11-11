import AgentConversation
import AgentProgram
import Foundation
import Testing

@Suite struct FakeAgentTests {
    @Test func aCommandLineThatClaudeCodeWouldRefuseEndsTheFakeAgent() async throws {
        let program = try AgentProgram(launching: AgentProgramLaunch(
            executablePath: FakeAgentRun.executable, arguments: ["-p", "--verbose"], folder: "/", environment: [:]))
        #expect(await program.waitForExit() == .exited(status: 64))
        #expect(program.standardErrorText.contains("arguments"))
    }
}
