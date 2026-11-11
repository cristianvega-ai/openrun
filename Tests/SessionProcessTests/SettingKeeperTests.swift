import DataStorage
import Foundation
import SessionProcessHarness
import Settings
import Testing
@testable import SessionProcess

@Suite struct SettingKeeperTests {
    @Test func aChangeIsOnTheDiskWhenItReturns() async throws {
        let data = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: data) }
        let store = SettingsStore(dataFolder: DataFolder(path: data.path))
        let keeper = SettingKeeper(store: store)
        let changed = try await keeper.change(name: "font-size", to: "15", requestedBy: .otherClient)
        #expect(changed.version == 1 && changed.values.fontSize == 15)
        #expect(try store.load().values.fontSize == 15)
        // The same value again writes nothing new.
        #expect(try await keeper.change(name: "font-size", to: " 15 ", requestedBy: .otherClient).version == 1)
        let restarted = await SettingKeeper(store: store).values
        #expect(restarted == changed.values)
    }

    @Test func onlyTheApplicationChangesAProtectedSetting() async throws {
        let data = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: data) }
        let keeper = SettingKeeper(store: SettingsStore(dataFolder: DataFolder(path: data.path)))
        await #expect(throws: SettingError.protectedSetting(.sessionLimit)) {
            try await keeper.change(name: "session-limit", to: "5", requestedBy: .otherClient)
        }
        await #expect(throws: SettingError.unknownName("colour")) { try await keeper.change(name: "colour", to: "red", requestedBy: .application) }
        await #expect(throws: SettingError.invalidValue(.fontSize)) { try await keeper.change(name: "font-size", to: "huge", requestedBy: .application) }
        #expect(try await keeper.change(name: "session-limit", to: "5", requestedBy: .application).values.sessionLimit == 5)
    }

    @Test func aFailedSaveKeepsTheValuesBeforeTheChange() async throws {
        let data = try RunningSessionProcess.makeDirectory()
        defer { chmod(data.path, 0o700); try? FileManager.default.removeItem(at: data) }
        let keeper = SettingKeeper(store: SettingsStore(dataFolder: DataFolder(path: data.path)))
        try #require(chmod(data.path, 0o500) == 0)
        await #expect(throws: DataSaveFailure.self) { try await keeper.change(name: "theme", to: "paper", requestedBy: .otherClient) }
        let (values, version) = (await keeper.values, await keeper.version)
        #expect(values == SettingValues() && version == 0)
    }

    @Test func aFileThatCannotBeReadDoesNotStopTheStart() async throws {
        let data = try RunningSessionProcess.makeDirectory()
        defer { try? FileManager.default.removeItem(at: data) }
        try Data(#"{"format":1,"font-size":"large","theme":"paper"}"#.utf8).write(to: data.appendingPathComponent("settings.json"))
        let values = await SettingKeeper(store: SettingsStore(dataFolder: DataFolder(path: data.path))).values
        #expect(values.fontSize == 13 && values.theme == "paper")
        try Data("{,".utf8).write(to: data.appendingPathComponent("settings.json"))
        let fallback = await SettingKeeper(store: SettingsStore(dataFolder: DataFolder(path: data.path))).values
        #expect(fallback == SettingValues())
        #expect(try FileManager.default.contentsOfDirectory(atPath: data.path).contains { $0.hasPrefix("settings.unreadable-") })
    }
}
