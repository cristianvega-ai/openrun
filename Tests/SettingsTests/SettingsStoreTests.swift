import DataStorage
import Foundation
import Settings
import Testing

@Suite struct SettingsStoreTests {
    let temporary: TemporaryFolder
    let folder: DataFolder
    let store: SettingsStore

    init() throws {
        temporary = try TemporaryFolder()
        folder = DataFolder(path: temporary.path + "/OpenRun")
        store = SettingsStore(dataFolder: folder)
    }

    func writeFile(_ text: String) throws {
        try folder.create()
        try Data(text.utf8).write(to: URL(fileURLWithPath: folder.path(of: .settings)))
    }

    @Test func noFileGivesTheDefaults() throws {
        let loaded = try store.load()
        #expect(loaded.values == SettingValues())
        #expect(loaded.fallbackNames.isEmpty)
        #expect(loaded.setAsidePath == nil)
    }

    @Test func everySettingRoundTripsThroughTheFile() throws {
        var values = SettingValues()
        for (name, text) in SettingChangeTests.changedTexts {
            try values.change(name, to: text, requestedBy: .application)
        }
        try store.save(values)
        #expect(try store.load().values == values)
    }

    @Test func theFileHoldsOnlyTheChangedSettings() throws {
        var values = SettingValues()
        try values.change(.fontSize, to: "15", requestedBy: .otherClient)
        try values.change(.theme, to: "graphite", requestedBy: .otherClient)
        try store.save(values)
        #expect(try String(contentsOfFile: folder.path(of: .settings), encoding: .utf8) == """
            {
              "format" : 1,
              "settings" : {
                "font-size" : 15
              }
            }

            """)
    }
}
