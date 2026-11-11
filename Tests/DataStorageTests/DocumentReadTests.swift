import DataStorage
import Foundation
import Testing

@Suite struct DocumentReadTests {
    static let sample = SampleDocument(name: "work", folder: "/work", count: 1)

    @Test func aMissingFileIsMissing() throws {
        let temporary = try TemporaryFolder()
        let result = try DataFolder(path: temporary.path).read(SampleDocument.self)
        guard case .missing = result else { Issue.record("\(result)"); return }
    }

    @Test func aWrittenDocumentReadsBack() throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path)
        try folder.write(Self.sample)
        #expect(try folder.read(SampleDocument.self).document == Self.sample)
    }

    @Test(arguments: [
        "not JSON",
        #"{"name": "work", "folder": "/work", "count": 1}"#,
        #"{"format": 3, "name": "work", "folder": "/work", "count": 1}"#,
        #"{"format": 0, "name": "work", "folder": "/work", "count": 1}"#,
        #"{"format": 2, "name": "work", "folder": "/work", "count": "one"}"#,
    ])
    func aFileThatCannotBeReadIsSetAsideWhole(content: String) throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path)
        try Data(content.utf8).write(to: URL(fileURLWithPath: folder.path(of: .layout)))
        let result = try folder.read(SampleDocument.self)
        guard case .setAside(let path) = result else { Issue.record("\(result)"); return }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == content)
        #expect(!FileManager.default.fileExists(atPath: folder.path(of: .layout)))
    }

    @Test func anOlderFormatStillReads() throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path)
        let content = #"{"format": 1, "name": "work", "folder": "/work", "count": 1}"#
        try Data(content.utf8).write(to: URL(fileURLWithPath: folder.path(of: .layout)))
        #expect(try folder.read(SampleDocument.self).document == Self.sample)
    }

    @Test func aFileOverTheSizeLimitIsSetAside() throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path)
        let large = Data(repeating: UInt8(ascii: " "), count: DataFolder.fileSizeLimit + 1)
        try large.write(to: URL(fileURLWithPath: folder.path(of: .layout)))
        let result = try folder.read(SampleDocument.self)
        guard case .setAside = result else { Issue.record("\(result)"); return }
    }
}
