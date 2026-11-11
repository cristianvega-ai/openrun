import AgentConversation
import ClaudeCodeAgent
import Foundation
import Testing

@Suite struct ClaudeCodeHistoryReaderTests {
    let history = Fixture.folder.appending(path: "history.jsonl")

    func allPages(_ reader: ClaudeCodeHistoryReader, pageByteCount: Int) throws -> [[ConversationEvent]] {
        var pages: [[ConversationEvent]] = []
        while !reader.hasReachedStart { pages.append(try reader.previousPage(pageByteCount: pageByteCount)) }
        #expect(try reader.previousPage() == [])
        return pages
    }

    @Test func theHistoryGivesOnlyWhatAChatShows() throws {
        let events = try ClaudeCodeHistoryReader(fileURL: history).previousPage()
        let input = JSONValue.object([
            "command": .string("touch held.txt"), "description": .string("Create held.txt in the working directory"),
        ])
        #expect(events.map(\.kind) == [
            .userMessage(UserMessage(
                identifier: "00000000-0000-4000-8000-000000000195",
                text: "Run the command `touch held.txt` with your Bash tool. Then reply with the single word ok.", isAccepted: true)),
            .toolCallInput(ToolCallInput(identifier: "toolu_01Fixture00000000000007", name: "Bash", input: input)),
            .toolCallResult(ToolCallResult(identifier: "toolu_01Fixture00000000000007", output: "(Bash completed with no output)", isError: false)),
            .agentText(AgentText(itemIdentifier: "msg_01Fixture00000000000014:0", text: "ok")),
            .turnEnded(TurnEnd(outcome: .done, durationMilliseconds: 1_234)),
        ])
        #expect(events.allSatisfy { $0.sourceLine?.text.contains("api-request-blob") == false })
    }

    @Test func smallPagesComeFromTheNewestAndGiveTheSameEvents() throws {
        let whole = try ClaudeCodeHistoryReader(fileURL: history).previousPage()
        let pages = try allPages(ClaudeCodeHistoryReader(fileURL: history), pageByteCount: 1)
        #expect(pages.count == 13)
        #expect(pages.first?.map(\.kind) == [.turnEnded(TurnEnd(outcome: .done, durationMilliseconds: 1_234))])
        #expect(Array(pages.reversed().joined()) == whole)
    }

    @Test func aFileThatGrowsWhileItIsReadGivesTheLinesOfItsStart() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "history-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        func line(_ index: Int) -> Data {
            Data(#"{"type":"user","isSidechain":false,"uuid":"u\#(index)","message":{"role":"user","content":"\#(index)"}}"#.utf8 + [10])
        }
        try (0..<500).reduce(into: Data()) { $0 += line($1) }.write(to: url)
        let writer = try FileHandle(forWritingTo: url)
        try writer.seekToEnd()
        // A half line, as when Claude Code writes while OpenRun opens the file.
        try writer.write(contentsOf: line(500).prefix(20))
        let appender = Task.detached {
            for index in 501..<3_000 { try writer.write(contentsOf: line(index)) }
            try writer.close()
        }
        let reader = try ClaudeCodeHistoryReader(fileURL: url)
        let events = try allPages(reader, pageByteCount: 4_096).reversed().joined()
        try await appender.value
        #expect(events.map(\.kind) == (0..<500).map {
            .userMessage(UserMessage(identifier: "u\($0)", text: "\($0)", isAccepted: true))
        })
    }
}
