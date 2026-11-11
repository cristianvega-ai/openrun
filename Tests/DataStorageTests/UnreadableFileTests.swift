@testable import DataStorage
import Foundation
import Testing

@Suite struct UnreadableFileTests {
    static let time = Date(timeIntervalSince1970: 1_794_303_000)

    @Test func theNewNameShowsTheTimeAndKeepsTheExtension() throws {
        let temporary = try TemporaryFolder()
        let path = temporary.path + "/settings.json"
        try Data("broken".utf8).write(to: URL(fileURLWithPath: path))
        let newPath = try UnreadableFile.setAside(path, at: Self.time)
        #expect(newPath == temporary.path + "/settings.unreadable-20261110T093000Z.json")
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(try String(contentsOfFile: newPath, encoding: .utf8) == "broken")
    }

    @Test func anEarlierUnreadableFileIsNeverWrittenOver() throws {
        let temporary = try TemporaryFolder()
        let path = temporary.path + "/settings.json"
        var newPaths: [String] = []
        for content in ["first", "second", "third"] {
            try Data(content.utf8).write(to: URL(fileURLWithPath: path))
            newPaths.append(try UnreadableFile.setAside(path, at: Self.time))
        }
        #expect(newPaths.map { ($0 as NSString).lastPathComponent } == [
            "settings.unreadable-20261110T093000Z.json",
            "settings.unreadable-20261110T093000Z-2.json",
            "settings.unreadable-20261110T093000Z-3.json",
        ])
        let contents = try newPaths.map { try String(contentsOfFile: $0, encoding: .utf8) }
        #expect(contents == ["first", "second", "third"])
    }
}
