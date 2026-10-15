import Foundation
import Synchronization
import Testing
@testable import TerminalEmulation

/// Collects replies. A terminal calls its handler on the writing thread, so
/// a plain class is safe here.
private final class ReplyRecorder {
    var replies: [[UInt8]] = []
    var text: String { String(decoding: replies.flatMap { $0 }, as: UTF8.self) }
}

private func makeRecordingTerminal() throws -> (Terminal, ReplyRecorder) {
    let terminal = try makeTerminal()
    let recorder = ReplyRecorder()
    try terminal.setReplyHandler { recorder.replies.append($0) }
    return (terminal, recorder)
}

@Suite struct TerminalReplyTests {
    @Test func aTerminalWithoutAHandlerStaysSilent() throws {
        let terminal = try makeTerminal()
        #expect(!terminal.hasReplyHandler)
        // Four queries: primary and secondary device attributes, the cursor
        // position, and the size in characters.
        terminal.write("ab\u{1B}[c\u{1B}[>c\u{1B}[6n\u{1B}[18t")
        // The queries print nothing and move nothing, and no reply came back
        // into the terminal as if the program had written it.
        #expect(try terminal.visibleText() == "ab")
        #expect(terminal.cursorPosition == TerminalCursorPosition(column: 2, row: 0))
        #expect(!terminal.hasReplyHandler)

        // Nobody saved the replies for later: a handler that comes now hears
        // only what is asked after it came.
        let recorder = ReplyRecorder()
        try terminal.setReplyHandler { recorder.replies.append($0) }
        #expect(recorder.replies.isEmpty, "replies to earlier queries arrived: \(recorder.text)")
        terminal.write("\u{1B}[6n")
        #expect(recorder.text == "\u{1B}[1;3R")
    }

    @Test func primaryDeviceAttributesQueryGetsOneReply() throws {
        let (terminal, recorder) = try makeRecordingTerminal()
        terminal.write("\u{1B}[c")
        #expect(recorder.text == "\u{1B}[?62;22c")
    }

    @Test func secondaryDeviceAttributesQueryGetsOneReply() throws {
        let (terminal, recorder) = try makeRecordingTerminal()
        terminal.write("\u{1B}[>c")
        #expect(recorder.replies.count == 1)
        #expect(recorder.text.hasPrefix("\u{1B}[>"))
    }

    @Test func cursorPositionQueryReportsTheCursor() throws {
        let (terminal, recorder) = try makeRecordingTerminal()
        terminal.write("abc\r\nde\u{1B}[6n")
        #expect(recorder.text == "\u{1B}[2;3R")
    }

    @Test func aQuerySplitAcrossWritesGetsOneReply() throws {
        let (terminal, recorder) = try makeRecordingTerminal()
        terminal.write("\u{1B}[")
        terminal.write("c")
        #expect(recorder.replies.count == 1)
    }

    @Test func removingTheHandlerSilencesTheTerminal() throws {
        let (terminal, recorder) = try makeRecordingTerminal()
        try terminal.setReplyHandler(nil)
        #expect(!terminal.hasReplyHandler)
        terminal.write("\u{1B}[c\u{1B}[6n")
        #expect(recorder.replies.isEmpty)
    }

    @Test func aRestoredTerminalInstallsNoHandler() throws {
        let (original, recorder) = try makeRecordingTerminal()
        original.write("hello")
        let restored = try TerminalSnapshot(capturing: original).restoreTerminal(scrollbackLimit: 100)
        #expect(!restored.hasReplyHandler)
        // Both terminals see the query, and only the original answers.
        original.write("\u{1B}[c")
        restored.write("\u{1B}[c")
        #expect(recorder.replies.count == 1)
    }

    @Test func replacingTheHandlerSendsRepliesToTheNewOne() throws {
        let (terminal, first) = try makeRecordingTerminal()
        let second = ReplyRecorder()
        try terminal.setReplyHandler { second.replies.append($0) }
        terminal.write("\u{1B}[6n")
        #expect(first.replies.isEmpty)
        #expect(second.replies.count == 1)
    }

    // MARK: - Size and color-scheme queries

    @Test func charactersSizeQueriesReportTheGrid() throws {
        let (terminal, recorder) = try makeRecordingTerminal()
        terminal.write("\u{1B}[18t")
        #expect(recorder.replies.count == 1)
        #expect(recorder.text == "\u{1B}[8;5;20t")
        terminal.write("\u{1B}[19t")
        #expect(recorder.replies.count == 2)
        #expect(String(decoding: recorder.replies.dropFirst().first ?? [], as: UTF8.self) == "\u{1B}[9;5;20t")
    }

    @Test func textAreaSizeQueriesUseTheNominalCell() throws {
        let (terminal, recorder) = try makeRecordingTerminal()
        terminal.write("\u{1B}[14t")
        // 5 rows of 16 pixels and 20 columns of 8 pixels.
        #expect(recorder.replies.count == 1)
        #expect(recorder.text == "\u{1B}[4;80;160t")
        terminal.write("\u{1B}[16t")
        #expect(recorder.replies.count == 2)
        #expect(String(decoding: recorder.replies.dropFirst().first ?? [], as: UTF8.self) == "\u{1B}[6;16;8t")
    }
}
