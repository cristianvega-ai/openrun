import AccountUsage
import DataStorage
import Foundation
import SessionProtocol
import Testing

@Suite struct AccountUsageStoreTests {
    @Test func theReadingsStayInTheDataFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "account-usage-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let store = AccountUsageStore(dataFolder: DataFolder(path: folder))
        #expect(store.load().isEmpty)
        let window = ThreadUsageWindow(name: "five_hour", lengthInMinutes: 300, usedFraction: 0.25, resetTime: Date(timeIntervalSince1970: 9_000), status: "allowed")
        let readings = [AccountUsageReading(agent: "codex", account: "Work", windows: [window], readAt: Date(timeIntervalSince1970: 8_000))]
        store.save(readings)
        store.finishWrites()
        // A new run of the app reads them again.
        #expect(AccountUsageStore(dataFolder: DataFolder(path: folder)).load() == readings)
        #expect(FileManager.default.fileExists(atPath: folder + "/account-usage.json"))
    }
}
