import DataStorage
import Darwin
import Foundation
import Testing

/// A write never replaces a file that this build could not read.
@Suite struct SafeReplaceTests {
    static let sample = SampleDocument(name: "work", folder: "/work", count: 1)

    @Test func aWriteSetsAsideAnUnreadableFileFirst() throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path)
        try Data("garbage".utf8).write(to: URL(fileURLWithPath: folder.path(of: .layout)))
        try folder.write(Self.sample)
        #expect(try folder.read(SampleDocument.self).document == Self.sample)
        let names = try FileManager.default.contentsOfDirectory(atPath: temporary.path)
        let setAside = try #require(names.first { $0.hasPrefix("layout.unreadable-") })
        #expect(try String(contentsOfFile: temporary.path + "/" + setAside, encoding: .utf8) == "garbage")
    }

    /// The reproduction of the review: the set-aside fails, so the load
    /// throws, and the write must throw too.
    @Test func aWriteThatCannotSetAsideChangesNothing() throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path)
        try Data("garbage".utf8).write(to: URL(fileURLWithPath: folder.path(of: .layout)))
        #expect(chmod(temporary.path, 0o500) == 0)
        defer { chmod(temporary.path, 0o700) }
        #expect(throws: DataStorageError.self) { try folder.read(SampleDocument.self) }
        try folder.create()
        #expect(throws: DataStorageError.self) { try folder.write(Self.sample) }
        #expect(try String(contentsOfFile: folder.path(of: .layout), encoding: .utf8) == "garbage")
    }

    /// The folder can be written, but the file cannot be read. Only the
    /// read before the write stops the replace.
    @Test func aWriteNeverReplacesAFileThatItCannotRead() throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path)
        let file = folder.path(of: .layout)
        try Data("only copy".utf8).write(to: URL(fileURLWithPath: file))
        #expect(chmod(file, 0o000) == 0)
        #expect(throws: DataStorageError.self) { try folder.write(Self.sample) }
        #expect(chmod(file, 0o600) == 0)
        #expect(try String(contentsOfFile: file, encoding: .utf8) == "only copy")
    }
}
