import Testing
@testable import AgentConversation

@Suite struct TranscriptStorageTests {
    func notice(_ text: String) -> TranscriptItemContent {
        .notice(Notice(level: .information, text: text))
    }

    @Test func anItemIsFoundByItsIdentifierAndChangesInPlace() {
        var storage = TranscriptStorage()
        storage.insert(TranscriptItem(identifier: "a", content: notice("one")))
        storage.insert(TranscriptItem(identifier: "b", content: notice("two")))
        #expect(storage.modify("b") { $0 = .notice(Notice(level: .warning, text: "three")) })
        #expect(!storage.modify("missing") { _ in })
        #expect(storage.item("b")?.content == .notice(Notice(level: .warning, text: "three")))
        #expect(storage.byteCount == 128 + "one".utf8.count + "three".utf8.count)
    }

    @Test func theOldestItemsGoFirstAndTheRestKeepTheirIdentifiers() {
        var storage = TranscriptStorage()
        for index in 0..<10 { storage.insert(TranscriptItem(identifier: "\(index)", content: notice(""))) }
        #expect(storage.trim(to: TranscriptLimits(itemLimit: 4)) == ["0", "1", "2", "3", "4", "5"])
        #expect(storage.items.map(\.identifier) == ["6", "7", "8", "9"])
        #expect(storage.removedItemCount == 6)
        #expect(!storage.contains("5"))
        #expect(storage.modify("7") { $0 = .notice(Notice(level: .error, text: "x")) })
        #expect(storage.item("7")?.content == .notice(Notice(level: .error, text: "x")))
        #expect(storage.byteCount == 4 * 64 + 1)
    }

    @Test func theByteLimitRemovesItemsButKeepsTheNewest() {
        var storage = TranscriptStorage()
        let big = String(repeating: "x", count: 1000)
        for index in 0..<3 { storage.insert(TranscriptItem(identifier: "\(index)", content: notice(big))) }
        #expect(storage.trim(to: TranscriptLimits(byteLimit: 100)) == ["0", "1"])
        #expect(storage.items.map(\.identifier) == ["2"])
    }
}
