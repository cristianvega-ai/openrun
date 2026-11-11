import DataStorage
import Foundation
import Testing
@testable import WindowLayout

@Suite struct WindowLayoutStoreTests {
    /// A store on a new folder, which the caller removes.
    private func makeStore() -> (store: WindowLayoutStore, folder: DataFolder) {
        let folder = DataFolder(path: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path)
        return (WindowLayoutStore(dataFolder: folder), folder)
    }

    @Test func theNewestLayoutThatWaitsIsWritten() {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(atPath: folder.path) }
        #expect(store.load() == WindowLayout())
        let rows = (0..<50).map { _ in LayoutRow(session: UUID()) }
        for count in 1...50 { store.save(WindowLayout(rows: Array(rows.prefix(count)))) }
        store.finishWrites()
        #expect(store.load() == WindowLayout(rows: rows))
        #expect(WindowLayoutStore(dataFolder: folder).load().rows.count == 50)
    }

    @Test func aFileThatCannotBeReadIsSetAsideAndTheLayoutStartsNew() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(atPath: folder.path) }
        try folder.create()
        try Data("not a layout".utf8).write(to: URL(fileURLWithPath: folder.path(of: .layout)))
        #expect(store.load() == WindowLayout())
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.contains { $0.hasPrefix("layout.unreadable-") })
        store.save(WindowLayout(filter: "finished"))
        store.finishWrites()
        #expect(store.load().filter == "finished")
    }
}
