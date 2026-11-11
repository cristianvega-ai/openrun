import DataStorage
import Foundation
import Testing

/// The reproductions of the second review: text that Foundation's decoder
/// takes but that is not strict JSON.
@Suite struct StrictReadTests {
    static let head = #"{"format": 2, "name": "a", "folder": "/a", "count": 1, "#

    static let contents: [[UInt8]] = [
        [0xEF, 0xBB, 0xBF] + Array((head + #""z": {"a": 1}}"#).utf8),
        Array((head + #""y": 2,}"#).utf8),
        Array((head + #""z": 01}"#).utf8),
        Array((head + #""z": [1,]}"#).utf8),
        Array((head + "\"z\": \"a\tb\"}").utf8),
        Array((head + #""z": "\q"}"#).utf8),
        Array((head + #""z": ""#).utf8) + [0xFF] + Array("\"}".utf8),
    ]

    /// After a load, a change and a save, the original bytes are in a
    /// set-aside file, and the new file is strict JSON.
    @Test(arguments: contents)
    func aFileThatIsNotStrictJSONIsSetAside(content: [UInt8]) throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path)
        try Data(content).write(to: URL(fileURLWithPath: folder.path(of: .layout)))
        let result = try folder.read(SampleDocument.self)
        guard case .setAside(let path) = result else { Issue.record("\(result)"); return }
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data(content))
        try folder.write(SampleDocument(name: "b", folder: "/b", count: 2))
        let written = try Data(contentsOf: URL(fileURLWithPath: folder.path(of: .layout)))
        #expect(try JSONSerialization.jsonObject(with: written) is [String: Any])
        #expect(try folder.read(SampleDocument.self).document == SampleDocument(name: "b", folder: "/b", count: 2))
    }

    /// A write that finds such a file sets it aside first too.
    @Test(arguments: contents)
    func aWriteSetsAsideAFileThatIsNotStrictJSON(content: [UInt8]) throws {
        let temporary = try TemporaryFolder()
        let folder = DataFolder(path: temporary.path)
        try Data(content).write(to: URL(fileURLWithPath: folder.path(of: .layout)))
        try folder.write(SampleDocument(name: "b", folder: "/b", count: 2))
        let names = try FileManager.default.contentsOfDirectory(atPath: temporary.path)
        let setAside = try #require(names.first { $0.hasPrefix("layout.unreadable-") })
        #expect(try Data(contentsOf: URL(fileURLWithPath: temporary.path + "/" + setAside)) == Data(content))
    }
}
