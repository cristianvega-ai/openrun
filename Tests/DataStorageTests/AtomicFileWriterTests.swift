@testable import DataStorage
import Darwin
import Foundation
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
}
