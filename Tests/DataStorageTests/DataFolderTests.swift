import DataStorage
import Darwin
import Foundation
import SessionProtocol
import Testing

@Suite struct DataFolderTests {
    static func mode(of path: String) -> mode_t {
        var status = stat()
        guard stat(path, &status) == 0 else { return 0 }
        return status.st_mode & 0o7777
    }

    /// The socket and the data share one folder, which OpenRun owns.
    @Test func theDefaultFolderHoldsTheDefaultSocket() {
        #expect(DataFolder.default.path == NSHomeDirectory() + "/Library/Application Support/OpenRun")
        #expect(SocketLocation.defaultPath == DataFolder.defaultPath + "/session.socket")
    }

    @Test func createMakesTheFolderAndItsParentsWithMode0700() throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path + "/parent/OpenRun")
        try folder.create()
        #expect(Self.mode(of: folder.path) == 0o700)
    }

    @Test func createGivesMode0700ToAFolderThatExists() throws {
        let temporary = try TemporaryFolder()
        #expect(chmod(temporary.path, 0o755) == 0)
        try DataFolder(path: temporary.path).create()
        #expect(Self.mode(of: temporary.path) == 0o700)
    }

    @Test func createTwiceKeepsTheFolderAndItsFiles() throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path + "/OpenRun")
        try folder.create()
        try Data("kept".utf8).write(to: URL(fileURLWithPath: folder.path + "/file"))
        try folder.create()
        #expect(try String(contentsOfFile: folder.path + "/file", encoding: .utf8) == "kept")
    }

    @Test func createRefusesAFileThatIsNotAFolder() throws {
        let temporary = try TemporaryFolder()
        let file = temporary.path + "/OpenRun"
        try Data().write(to: URL(fileURLWithPath: file))
        #expect(throws: DataStorageError.notAFolder(path: file)) {
            try DataFolder(path: file).create()
        }
    }

    @Test func createRemovesOnlyOldTemporaryFiles() throws {
        let temporary = try TemporaryFolder()
        let old = temporary.path + "/.settings.json.1.writing"
        let new = temporary.path + "/.settings.json.2.writing"
        let other = temporary.path + "/.hidden"
        for file in [old, new, other] { try Data().write(to: URL(fileURLWithPath: file)) }
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: other)
        try DataFolder(path: temporary.path).create()
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: temporary.path))
        #expect(names == [".settings.json.2.writing", ".hidden"])
    }
}
