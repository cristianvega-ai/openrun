import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexThreadStartTests {
    @Test func aThreadAsksBeforeEachCommandOutsideItsSandbox() {
        let start = CodexThreadStart(folder: "/work/project", model: "gpt-example", reasoningEffort: "low")
        #expect(start.parameters == [
            "cwd": .string("/work/project"), "approvalPolicy": .string("untrusted"), "sandbox": .string("workspace-write"),
            "model": .string("gpt-example"), "config": .object(["model_reasoning_effort": .string("low")]),
        ])
    }

    @Test func aThreadWithoutAModelTakesTheConfigurationOfTheUser() {
        let start = CodexThreadStart(folder: "/work/project", sandbox: .readOnly)
        #expect(start.parameters["model"] == nil)
        #expect(start.parameters["config"] == nil)
        #expect(start.parameters["sandbox"] == .string("read-only"))
        #expect(CodexSandbox.readOnly.turnValue == .object(["type": .string("readOnly")]))
    }
}
