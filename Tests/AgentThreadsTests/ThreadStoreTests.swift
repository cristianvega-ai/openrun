import DataStorage
import Foundation
import Testing
@testable import AgentThreads

@Suite struct ThreadStoreTests {
    private func makeStore() -> ThreadStore {
        ThreadStore(dataFolder: DataFolder(path: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path))
    }

    @Test func theThreadsComeBackAsTheyWereSaved() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(atPath: store.dataFolder.path) }
        #expect(try store.load().list == ThreadList())
        var list = ThreadList()
        var record = ThreadListTests.record(name: "Release")
        record.account = ThreadAccount(name: "Work", settingsFolder: "/Users/ana/.claude-work")
        (record.title, record.hasConversation) = ("Write the notes", true)
        try list.add(record)
        try list.add(ThreadListTests.record())
        try store.save(list)
        let loaded = try store.load()
        #expect(loaded.list == list && loaded.setAsidePath == nil)
        let text = try String(contentsOfFile: store.dataFolder.path(of: .threads), encoding: .utf8)
        #expect(text.contains("\"agent\" : \"claude-code\"") && text.contains("\"format\" : 1"))
    }

    @Test func aBadRecordIsLeftOutAndABadFileIsSetAside() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(atPath: store.dataFolder.path) }
        let good = ThreadListTests.record(), bad = ThreadListTests.record(model: "--flag")
        try store.dataFolder.create()
        try store.dataFolder.write(ThreadStore.Document(threads: [good, bad, good]))
        #expect(try store.load().list.threads == [good])
        try Data("not JSON".utf8).write(to: URL(fileURLWithPath: store.dataFolder.path(of: .threads)))
        let loaded = try store.load()
        #expect(loaded.list.threads.isEmpty && loaded.setAsidePath?.contains("threads.unreadable-") == true)
    }
}
