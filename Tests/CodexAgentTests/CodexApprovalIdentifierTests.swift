import AgentConversation
import Testing
@testable import CodexAgent

/// The identifiers of the approval requests of Codex.
@Suite struct CodexApprovalIdentifierTests {
    func request(_ identifier: String, item: String) -> String {
        #"{"id":\#(identifier),"method":"item/commandExecution/requestApproval","params":{"threadId":"a","itemId":"\#(item)","command":"ls"}}"#
    }

    @Test func aWithdrawalNamesARequestAboveTwoToTheFiftyThird() async throws {
        let harness = try await CodexServerHarness()
        let thread = await harness.server.open("a", first: [])
        harness.serve(request("9007199254740993", item: "i"))
        harness.serve(#"{"method":"serverRequest/resolved","params":{"threadId":"a","requestId":9007199254740993}}"#)
        guard case .permissionRequested(let request)? = await thread.next()?.kind else { Issue.record("No request"); return }
        #expect(request.identifier == "i/9007199254740993")
        guard case .permissionEnded(let end)? = await thread.next()?.kind else { Issue.record("No end"); return }
        #expect(end.outcome == .cancelled)
    }
}
