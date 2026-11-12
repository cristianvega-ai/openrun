import DataStorage
import Testing

@Suite struct DataFileTests {
    /// The names are in the decision log and in the architecture document,
    /// so a change must not pass unseen.
    @Test func eachFileHasItsNameAndScope() {
        #expect(DataFile.projects.name == "projects.json")
        #expect(DataFile.projects.scope == .shared)
        #expect(DataFile.projectFolders.name == "project-folders.json")
        #expect(DataFile.projectFolders.scope == .thisMac)
        #expect(DataFile.settings.name == "settings.json")
        #expect(DataFile.settings.scope == .shared)
        #expect(DataFile.layout.name == "layout.json")
        #expect(DataFile.layout.scope == .thisMac)
        #expect(DataFile.sessions.name == "sessions.json" && DataFile.sessions.scope == .thisMac)
        #expect(Set(DataFile.all.map(\.name)).count == DataFile.all.count)
    }

    @Test func aFileIsInsideItsFolder() {
        let folder = DataFolder(path: "/data/OpenRun")
        #expect(folder.path(of: .settings) == "/data/OpenRun/settings.json")
    }
}

@Suite struct DataStorageErrorTests {
    @Test func aPathInAMessageHasNoControlCharacter() {
        for error in [DataStorageError.notAFolder(path: "/a\u{1B}[2J"), .folderNotCreated(path: "/a\u{1B}[2J")] {
            #expect(!error.description.contains("\u{1B}"))
            #expect(error.description.contains(#""/a\u{1B}[2J""#))
        }
    }
}
