import DataStorage
import Foundation
import Testing

@Suite struct DocumentWriteTests {
    @Test func theFileIsReadableJSONWithTheFormatNumber() throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path)
        try folder.write(SampleDocument(name: "Ünïcode", folder: "/Users/someone/work", count: 3))
        let text = try String(contentsOfFile: folder.path(of: .layout), encoding: .utf8)
        #expect(text == """
            {
              "count" : 3,
              "folder" : "/Users/someone/work",
              "format" : 2,
              "name" : "Ünïcode"
            }

            """)
        #expect(DataFolderTests.mode(of: folder.path(of: .layout)) == 0o600)
    }
}
