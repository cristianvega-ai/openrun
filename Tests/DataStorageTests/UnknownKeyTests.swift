import DataStorage
import Foundation
import Testing

/// A key of a later build stays in the file, with the exact text of its
/// value, when this build writes the file again.
@Suite struct UnknownKeyTests {
    @Test func aWriteKeepsTheUnknownKeysAsTheyAre() throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path)
        try Data(#"""
            {"format": 2, "name": "old", "folder": "/old", "count": 1, "note": "gone",
             "later": {"large": 123456789012345678901234567890, "zero": -0.0}, "unsigned": 18446744073709551615}
            """#.utf8).write(to: URL(fileURLWithPath: folder.path(of: .layout)))
        try folder.write(SampleDocument(name: "new", folder: "/new", count: 2))
        let text = try String(contentsOfFile: folder.path(of: .layout), encoding: .utf8)
        #expect(text == """
            {
              "count" : 2,
              "folder" : "/new",
              "format" : 2,
              "later" : {"large": 123456789012345678901234567890, "zero": -0.0},
              "name" : "new",
              "unsigned" : 18446744073709551615
            }

            """)
        #expect(try folder.read(SampleDocument.self).document == SampleDocument(name: "new", folder: "/new", count: 2))
    }
}
