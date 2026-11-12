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

    @Test func aPageOfTurnsStartsAtAMessageOfTheUserAndALaterReaderGoesOn() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "history-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        // Three turns: a message of the user, an answer, and the end of the turn.
        let lines = (1...3).flatMap { turn in [
            #"{"type":"user","uuid":"u\#(turn)","message":{"role":"user","content":"Question \#(turn)"}}"#,
            #"{"type":"assistant","message":{"id":"m\#(turn)","content":[{"type":"text","text":"Answer \#(turn)"}]}}"#,
            #"{"type":"system","subtype":"turn_duration","durationMs":\#(turn)}"#,
        ] }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        func turn(_ number: Int) -> [ConversationEventKind] { [
            .userMessage(UserMessage(identifier: "u\(number)", text: "Question \(number)", isAccepted: true)),
            .agentText(AgentText(itemIdentifier: "m\(number):0", text: "Answer \(number)")),
            .turnEnded(TurnEnd(outcome: .done, durationMilliseconds: number)),
        ] }

        // A page that is smaller than a turn is one whole turn.
        let reader = try ClaudeCodeHistoryReader(fileURL: url)
        #expect(try reader.previousTurns(pageByteCount: 40).map(\.kind) == turn(3))
        // A new reader at the cursor gives the turns before it.
        let later = try ClaudeCodeHistoryReader(fileURL: url, before: reader.cursor)
        #expect(try later.previousTurns(pageByteCount: 300).map(\.kind) == turn(1) + turn(2))
        #expect(later.hasReachedStart && later.cursor == 0)
        #expect(try ClaudeCodeHistoryReader(fileURL: url, before: 0).previousTurns() == [])
        // The lines after an earlier size of the file are the turns that came since, such as in a terminal.
        let secondTurn = UInt64((lines.prefix(3).joined(separator: "\n") + "\n").utf8.count)
        #expect(try ClaudeCodeHistoryReader.events(inFileAt: url, after: secondTurn).map(\.kind) == turn(2) + turn(3))
        #expect(try ClaudeCodeHistoryReader.events(inFileAt: url, after: later.cursor + 10_000).isEmpty)
        // A turn that is longer than eight pages gives a page that starts in the turn.
        let long = (0..<40).map { #"{"type":"assistant","message":{"id":"x\#($0)","content":[{"type":"text","text":"A"}]}}"# }
        try Data(((lines.prefix(1) + long).joined(separator: "\n") + "\n").utf8).write(to: url)
        let cut = try ClaudeCodeHistoryReader(fileURL: url).previousTurns(pageByteCount: 100)
        #expect(cut.count < 40 && cut.count >= 8 && !cut.contains { if case .userMessage = $0.kind { true } else { false } })
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
