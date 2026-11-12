import DataStorage
import Foundation
import Testing
@testable import SessionRecords

@Suite struct SessionRecordStoreTests {
    private func makeStore() -> SessionRecordStore {
        SessionRecordStore(dataFolder: DataFolder(path: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path))
    }

    private func record(folder: String = "/work/app", name: String? = nil, columns: Int = 80, at seconds: Double = 0) -> SessionRecord {
        SessionRecord(identifier: UUID(), folder: folder, name: name, columns: columns, rows: 24, createdAt: Date(timeIntervalSince1970: seconds))
    }

    @Test func theRecordsComeBackOldestFirst() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(atPath: store.dataFolder.path) }
        #expect(try store.load().records.isEmpty)
        let (newer, older) = (record(name: "Build", at: 20), record(folder: "/work/site", at: 10))
        try store.save([newer, older])
        let loaded = try store.load()
        #expect(loaded.records == [older, newer] && loaded.setAsidePath == nil)
        let text = try String(contentsOfFile: store.dataFolder.path(of: .sessions), encoding: .utf8)
        #expect(text.contains("\"folder\" : \"/work/site\"") && text.contains("\"format\" : 1") && !text.contains("environment"))
        try store.save([])
        #expect(try store.load().records.isEmpty)
    }

    @Test func aBadRecordIsLeftOutAndABadFileIsSetAside() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(atPath: store.dataFolder.path) }
        let good = record()
        let bad = [record(folder: "relative"), record(columns: 0), record(name: String(repeating: "n", count: 501))]
        try store.dataFolder.create()
        try store.dataFolder.write(SessionRecordStore.Document(sessions: [good] + bad + [good]))
        #expect(try store.load().records == [good])
        try Data("not JSON".utf8).write(to: URL(fileURLWithPath: store.dataFolder.path(of: .sessions)))
        let loaded = try store.load()
        #expect(loaded.records.isEmpty && loaded.setAsidePath?.contains("sessions.unreadable-") == true)
    }
}
