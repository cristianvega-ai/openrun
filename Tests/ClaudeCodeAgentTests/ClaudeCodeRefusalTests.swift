import AgentConversation
import ClaudeCodeAgent
import Foundation
import Testing

/// The reason of a refusal tells the user who refused, so a hook that
/// failed must not look like an answer of the user.
@Suite struct ClaudeCodeRefusalTests {
    func refusal(type: String?, reason: String) throws -> ToolCallRefusal {
        var line: [String: Any] = [
            "type": "system", "subtype": "permission_denied", "tool_name": "Bash", "tool_use_id": "toolu_01Fixture00000000000099",
            "decision_reason": reason, "message": reason,
        ]
        line["decision_reason_type"] = type
        var decoder = ClaudeCodeOutputDecoder()
        let bytes = try JSONSerialization.data(withJSONObject: line) + Data("\n".utf8)
        guard case .toolCallRefused(let refusal)? = decoder.decode(Array(bytes)).first?.kind else { throw CancellationError() }
        return refusal
    }

    @Test func aHookThatDeniedIsTheUser() throws {
        let refusal = try refusal(type: "hook", reason: "The user denied this command.")
        #expect(refusal.reason == .user)
        #expect(refusal.message == "The user denied this command.")
    }

    @Test(arguments: [
        "[/opt/openrun/hook claude]: failed; blocking because onFailure is \"block\"\nNo stderr output",
        "[/opt/openrun/hook claude]: failed; blocking because onFailure is \"block\"\nTraceback (most recent call last):",
        "[/opt/openrun/hook claude]: failed",
    ])
    func aHookThatFailedIsUnanswered(reason: String) throws {
        let refusal = try refusal(type: "hook", reason: reason)
        #expect(refusal.reason == .unanswered)
        #expect(refusal.message == reason)
    }

    @Test func theOtherReasonsKeepTheirMeaning() throws {
        #expect(try refusal(type: "rule", reason: "Denied by a rule.").reason == .rule)
        #expect(try refusal(type: "mode", reason: "Denied in this mode.").reason == .mode)
        #expect(try refusal(type: nil, reason: "touch needs approval.").reason == .unanswered)
        #expect(try refusal(type: "classifier", reason: "No.").reason == .other)
    }
}
