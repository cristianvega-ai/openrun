import ClaudeCodeAgent
import Foundation
import Testing

@Suite struct ClaudeCodeHistoryLocationTests {
    let conversation = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!

    @Test func eachCodeUnitThatIsNotALetterOrDigitBecomesAHyphen() {
        #expect(ClaudeCodeHistoryLocation.projectFolderName(workingFolder: "/private/tmp/agent-1/-Users-x/a.b_c d")
            == "-private-tmp-agent-1--Users-x-a-b-c-d")
        #expect(ClaudeCodeHistoryLocation.projectFolderName(workingFolder: "/é😀Z9") == "----Z9")
    }

    @Test func theFileIsInTheProjectFolderOfTheConfigurationFolder() {
        let home = URL(fileURLWithPath: "/home/someone", isDirectory: true)
        #expect(ClaudeCodeHistoryLocation.configurationFolder(environment: ["CLAUDE_CONFIG_DIR": ""], homeFolder: home).path == "/home/someone/.claude")
        let configuration = ClaudeCodeHistoryLocation.configurationFolder(environment: ["CLAUDE_CONFIG_DIR": "/config/claude"], homeFolder: home)
        #expect(ClaudeCodeHistoryLocation.fileURL(
            configurationFolder: configuration, workingFolder: "/work/project", conversationIdentifier: conversation).path
            == "/config/claude/projects/-work-project/00000000-0000-4000-8000-000000000003.jsonl")
    }

    @Test func theFileIsFoundAlsoThroughALinkOrUnderAnotherName() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "history-location-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = root.appending(path: "configuration")
        let real = root.appending(path: "real").path
        try FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
        let link = root.appending(path: "link").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        let resolved = try #require(realpath(real, nil))
        defer { free(resolved) }
        let expected = ClaudeCodeHistoryLocation.fileURL(
            configurationFolder: configuration, workingFolder: String(cString: resolved), conversationIdentifier: conversation)
        #expect(ClaudeCodeHistoryLocation.locate(configurationFolder: configuration, workingFolder: link, conversationIdentifier: conversation) == nil)
        try FileManager.default.createDirectory(at: expected.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: expected)
        #expect(ClaudeCodeHistoryLocation.locate(configurationFolder: configuration, workingFolder: link, conversationIdentifier: conversation) == expected)
        let shortened = configuration.appending(path: "projects/-shortened-name-1a2b/00000000-0000-4000-8000-000000000003.jsonl")
        try FileManager.default.createDirectory(at: shortened.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: expected, to: shortened)
        #expect(ClaudeCodeHistoryLocation.locate(configurationFolder: configuration, workingFolder: link, conversationIdentifier: conversation)?
            .resolvingSymlinksInPath() == shortened.resolvingSymlinksInPath())
    }
}
