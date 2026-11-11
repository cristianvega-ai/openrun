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
}
