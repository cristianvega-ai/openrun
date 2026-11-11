import DataStorage
import Darwin
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
              "font-size" : 15,
              "format" : 1
            }

            """)
    }

    @Test func anUnknownSettingStaysWhenTheFileIsSavedAgain() throws {
        try writeFile(#"""
            {"format": 1, "later-setting": {"deep": [1, 2.5, "x", null], "large": 123456789012345678901234567890},
             "later-limit": 18446744073709551615, "later-zero": -0.0, "font-size": 20, "theme": "dusk"}
            """#)
        var values = try store.load().values
        #expect(values.fontSize == 20)
        try values.change(.fontSize, to: "21", requestedBy: .otherClient)
        try values.change(.theme, to: "graphite", requestedBy: .otherClient)
        try store.save(values)
        let text = try String(contentsOfFile: folder.path(of: .settings), encoding: .utf8)
        #expect(text == """
            {
              "font-size" : 21,
              "format" : 1,
              "later-limit" : 18446744073709551615,
              "later-setting" : {"deep": [1, 2.5, "x", null], "large": 123456789012345678901234567890},
              "later-zero" : -0.0
            }

            """)
        #expect(try store.load().values == values)
        #expect(throws: SettingError.unknownName("later-setting")) { try SettingName.named("later-setting") }
    }

    @Test func aBadValueFallsBackAloneToItsDefault() throws {
        try writeFile("""
            {"format": 1, "font-size": 500, "theme": 7, "notifications": "off",
             "scrollback-limit": 0, "font-name": "Menlo", "option-as-alt": "right"}
            """)
        let loaded = try store.load()
        #expect(loaded.fallbackNames == [.fontSize, .showsNotifications, .optionAsAlt, .theme])
        #expect(loaded.values.fontSize == 13)
        #expect(loaded.values.theme == "graphite")
        #expect(loaded.values.showsNotifications)
        #expect(loaded.values.optionAsAlt == .left)
        #expect(loaded.values.scrollbackLimit == 0)
        #expect(loaded.values.fontName == "Menlo")
    }

    @Test func aCorruptFileIsSetAside() throws {
        try writeFile(#"{"format": 1, "font-size": 2"#)
        let loaded = try store.load()
        #expect(loaded.values == SettingValues())
        let path = try #require(loaded.setAsidePath)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == #"{"format": 1, "font-size": 2"#)
        #expect(!FileManager.default.fileExists(atPath: folder.path(of: .settings)))
    }

    /// The reproduction of the review: a load that fails and a save after it.
    @Test func aSaveAfterAFailedLoadChangesNothing() throws {
        try writeFile("garbage")
        #expect(chmod(folder.path, 0o500) == 0)
        defer { chmod(folder.path, 0o700) }
        #expect(throws: DataStorageError.self) { try store.load() }
        #expect(throws: DataStorageError.self) { try store.save(SettingValues()) }
        #expect(try String(contentsOfFile: folder.path(of: .settings), encoding: .utf8) == "garbage")
    }
}
