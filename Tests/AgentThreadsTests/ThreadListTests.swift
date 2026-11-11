import Foundation
import Testing
@testable import AgentThreads

@Suite struct ThreadListTests {
    static func record(_ identifier: UUID = UUID(), folder: String = "/work/app", model: String = "opus", mode: String = "default", name: String? = nil) -> ThreadRecord {
        ThreadRecord(identifier: identifier, agent: .claudeCode, folder: folder, model: model, permissionMode: mode, name: name,
                     createdAt: Date(timeIntervalSince1970: 1_000))
    }

    @Test func aNewThreadOfClaudeCodeHasItsOwnIdentifierAsTheConversation() {
        let record = Self.record()
        #expect(record.conversationIdentifier == record.identifier.uuidString.lowercased())
        #expect(!record.hasConversation && record.account == nil && record.lastActivityAt == record.createdAt)
        #expect(ThreadAgent.claudeCode.shownName == "Claude Code" && ThreadAgent(rawValue: "codex") == .codex)
    }

    @Test func theListAddsChangesAndRemovesThreads() throws {
        var list = ThreadList()
        let first = Self.record(), second = Self.record(name: "  Release notes ")
        try list.add(first)
        try list.add(second)
        #expect(list.threads.map(\.identifier) == [first.identifier, second.identifier] && list.thread(second.identifier)?.name == "Release notes")
        try list.update(first.identifier) { $0.name = "   " ; $0.hasConversation = true }
        #expect(list.thread(first.identifier)?.name == nil && list.thread(first.identifier)?.hasConversation == true)
        try list.remove(first.identifier)
        #expect(list.threads.map(\.identifier) == [second.identifier])
        #expect(throws: ThreadListError.unknownThread(first.identifier)) { try list.remove(first.identifier) }
        #expect(throws: ThreadListError.unknownThread(first.identifier)) { try list.update(first.identifier) { $0.name = "x" } }
        #expect(throws: ThreadListError.duplicateThread(second.identifier)) { try list.add(second) }
    }

    @Test func aValueThatCouldHarmAListOrACommandLineIsRefused() throws {
        var list = ThreadList()
        #expect(throws: ThreadListError.invalidName) { try list.add(Self.record(name: "a\u{1B}[31mb")) }
        #expect(throws: ThreadListError.invalidName) { try list.add(Self.record(name: String(repeating: "n", count: 101))) }
        #expect(throws: ThreadListError.invalidFolder) { try list.add(Self.record(folder: "work/app")) }
        #expect(throws: ThreadListError.invalidFolder) { try list.add(Self.record(folder: "/work/\0app")) }
        #expect(throws: ThreadListError.invalidModel) { try list.add(Self.record(model: "--dangerously-skip-permissions")) }
        #expect(throws: ThreadListError.invalidModel) { try list.add(Self.record(model: "")) }
        #expect(throws: ThreadListError.invalidPermissionMode) { try list.add(Self.record(mode: "plan mode")) }
        let good = Self.record()
        try list.add(good)
        #expect(throws: ThreadListError.invalidModel) { try list.update(good.identifier) { $0.model = "a b" } }
        #expect(list.thread(good.identifier)?.model == "opus" && list.threads.count == 1)
    }

    @Test func theListHoldsAtMostOneThousandThreads() throws {
        var list = ThreadList()
        for _ in 0..<ThreadList.countLimit { try list.add(Self.record()) }
        #expect(throws: ThreadListError.tooManyThreads(limit: 1_000)) { try list.add(Self.record()) }
        #expect(ThreadListError.tooManyThreads(limit: 1_000).description == "OpenRun keeps at most 1000 threads. Close a thread first.")
    }

    @Test func theTitleIsTheStartOfAMessageAsOnePlainLine() {
        #expect(ThreadList.title(from: "  Repair the\n\tresize\u{1B}[0m  of the pane ") == "Repair the resize [0m of the pane")
        #expect(ThreadList.title(from: String(repeating: "word ", count: 40)).count == 80)
        #expect(ThreadList.title(from: "a\u{202E}b") == "a b")
    }
}
