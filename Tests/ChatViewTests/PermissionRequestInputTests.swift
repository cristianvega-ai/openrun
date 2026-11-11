import AgentConversation
import Testing

@testable import ChatView

struct PermissionRequestInputTests {
    @Test func takenMembersLeaveTheRestAndNothingElseHides() {
        var input = PermissionRequestInput(.object([
            "command": .array([.string("rm"), .string("-rf"), .string("build")]),
            "timeout": .number(60_000), "flags": .object(["sandbox": .bool(false)]), "note": .string("a\nb"),
        ]))
        #expect(input.text("command") == "rm -rf build")
        #expect(input.text("timeout") == nil)
        #expect(input.rest == "flags: {\n  \"sandbox\" : false\n}\nnote: a\nb\ntimeout: 60000")
    }

    @Test func inputThatIsNoObjectStillShows() {
        #expect(PermissionRequestInput(.string("ls")).rest == "input: ls")
        #expect(PermissionRequestInput(.null).rest == "")
    }
}
