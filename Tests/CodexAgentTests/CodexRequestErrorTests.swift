import Testing
@testable import CodexAgent

@Suite struct CodexRequestErrorTests {
    @Test func eachErrorSaysWhatHappened() {
        #expect(CodexRequestError.refused(code: -32600, message: "no rollout found").description
            == "Codex refused the request (-32600): no rollout found")
        #expect(CodexRequestError.timedOut(method: "thread/start").description == "Codex gave no answer to thread/start in the time limit.")
        #expect(CodexRequestError.connectionEnded.description == "The Codex app-server ended before it answered.")
    }
}
