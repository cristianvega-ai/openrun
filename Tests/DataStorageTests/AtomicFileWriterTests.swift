@testable import DataStorage
import Darwin
import Foundation
import Synchronization
import Testing

@Suite struct AtomicFileWriterTests {
    @Test func theFileHasMode0600AndTheContent() throws {
        let temporary = try TemporaryFolder()
        let path = temporary.path + "/file.json"
        try AtomicFileWriter.write(Data("first".utf8), to: path)
        #expect(DataFolderTests.mode(of: path) == 0o600)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data("first".utf8))
    }

    @Test func aWriteReplacesTheFileAndLeavesNoTemporaryFile() throws {
        let temporary = try TemporaryFolder()
        let path = temporary.path + "/file.json"
        try AtomicFileWriter.write(Data("a longer first content".utf8), to: path)
        try AtomicFileWriter.write(Data("second".utf8), to: path)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data("second".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.path) == ["file.json"])
    }

    @Test func aFailedWriteLeavesTheOldFile() throws {
        let temporary = try TemporaryFolder()
        let path = temporary.path + "/file.json"
        try AtomicFileWriter.write(Data("old".utf8), to: path)
        #expect(chmod(temporary.path, 0o500) == 0)
        defer { chmod(temporary.path, 0o700) }
        #expect(throws: DataStorageError.self) { try AtomicFileWriter.write(Data("new".utf8), to: path) }
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data("old".utf8))
    }

    /// A reader that reads while the writer replaces the file again and
    /// again only ever finds one whole content.
    @Test func aReaderNeverSeesAPartialFile() async throws {
        let temporary = try TemporaryFolder()
        let path = temporary.path + "/file.json"
        let small = Data(repeating: UInt8(ascii: "a"), count: 100_000)
        let large = Data(repeating: UInt8(ascii: "b"), count: 1_000_000)
        try AtomicFileWriter.write(small, to: path)
        let done = Atomic(false)
        let reader = Task.detached { () -> (reads: Int, partial: Int) in
            var reads = 0, partial = 0
            while !done.load(ordering: .relaxed) {
                guard let content = FileManager.default.contents(atPath: path) else { partial += 1; continue }
                reads += 1
                if content != small && content != large { partial += 1 }
            }
            return (reads, partial)
        }
        for round in 0..<40 {
            try AtomicFileWriter.write(round.isMultiple(of: 2) ? large : small, to: path)
        }
        done.store(true, ordering: .relaxed)
        let result = await reader.value
        #expect(result.reads > 0)
        #expect(result.partial == 0)
    }
}
