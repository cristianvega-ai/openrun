import AgentConversation
import Testing
@testable import CodexAgent

@Suite struct CodexFileChangesTests {
    func item(_ changes: [JSONValue]) -> JSONValue {
        .object(["type": .string("fileChange"), "id": .string("exec-1"), "changes": .array(changes)])
    }

    func change(_ path: String, _ kind: JSONValue, _ diff: String) -> JSONValue {
        .object(["path": .string(path), "kind": kind, "diff": .string(diff)])
    }

    @Test func theContentOfANewFileBecomesAddedLines() {
        let changes = CodexFileChanges.changes(of: item([change("/work/project/notes.txt", .object(["type": .string("add")]), "hi\n")]))
        #expect(changes == [FileChange(
            identifier: "exec-1:0", toolCallIdentifier: "exec-1", path: "/work/project/notes.txt", kind: .added, diff: "@@ -0,0 +1,1 @@\n+hi")])
    }

    @Test func theContentOfADeletedFileBecomesRemovedLines() {
        let changes = CodexFileChanges.changes(of: item([change("a.txt", .object(["type": .string("delete")]), "one\ntwo")]))
        #expect(changes.map(\.diff) == ["@@ -1,2 +0,0 @@\n-one\n-two"])
        #expect(changes.map(\.kind) == [.deleted])
    }

    @Test func aChangedFileKeepsItsDiffAndAMoveNamesBothPaths() {
        let diff = "@@ -1 +1 @@\n-a\n+b\n"
        let changes = CodexFileChanges.changes(of: item([
            change("a.txt", .object(["type": .string("update"), "move_path": .null]), diff),
            change("b.txt", .object(["type": .string("update"), "move_path": .string("c.txt")]), diff),
        ]))
        #expect(changes.map(\.identifier) == ["exec-1:0", "exec-1:1"])
        #expect(changes.map(\.path) == ["a.txt", "b.txt → c.txt"])
        #expect(changes.allSatisfy { $0.kind == .modified && $0.diff == diff })
    }

    @Test func anItemWithoutChangesGivesNone() {
        #expect(CodexFileChanges.changes(of: .object(["type": .string("fileChange")])).isEmpty)
    }
}
