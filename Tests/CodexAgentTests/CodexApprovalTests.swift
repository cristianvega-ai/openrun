import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexApprovalTests {
    func approval(_ method: String, _ parameters: JSONValue) -> CodexApproval {
        CodexApproval(thread: "t", request: .number(2), item: "exec-1", method: method, parameters: parameters, timer: Task {})
    }

    @Test func aCommandShowsItsCommandAndFolder() {
        let parameters = JSONValue.object(["command": .string("/bin/zsh -lc 'touch x1.txt'"), "cwd": .string("/work/project")])
        let request = approval(CodexApproval.commandMethod, parameters).permissionRequest(identifier: "exec-1/2", startedItem: nil)
        #expect(request == PermissionRequest(identifier: "exec-1/2", toolName: "commandExecution", input: .object([
            "command": .string("/bin/zsh -lc 'touch x1.txt'"), "cwd": .string("/work/project"), "reason": .null,
        ]), toolCallIdentifier: "exec-1"))
    }

    @Test func aFileChangeShowsTheDiffFromTheStartOfItsItem() {
        let started = JSONValue.object(["id": .string("exec-1"), "changes": .array([.object([
            "path": .string("/work/project/notes.txt"), "kind": .object(["type": .string("add")]), "diff": .string("hi\n"),
        ])])])
        let request = approval(CodexApproval.fileChangeMethod, .object(["reason": .null]))
            .permissionRequest(identifier: "exec-1/2", startedItem: started)
        #expect(request.toolName == "fileChange")
        #expect(request.input["changes"] == .array([.object([
            "path": .string("/work/project/notes.txt"), "kind": .string("added"), "diff": .string("@@ -0,0 +1,1 @@\n+hi"),
        ])]))
        #expect(CodexPermissionAnswer.allow.decision == "accept")
        #expect(CodexPermissionAnswer.deny.decision == "decline")
    }
}
