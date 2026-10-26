import Testing
@testable import TerminalEmulation

private final class EventRecorder {
    var events: [String] = []
    var handler: TerminalEventHandler {
        TerminalEventHandler(
            bell: { self.events.append("bell") },
            titleChanged: { self.events.append("title") },
            renderHold: { self.events.append($0 ? "hold" : "release") }
        )
    }
}

@Suite struct TerminalEventHandlerTests {
    @Test func reportsTheBellTheTitleAndRenderHolds() throws {
        let terminal = try makeTerminal()
        let recorder = EventRecorder()
        try terminal.setEventHandler(recorder.handler)
        terminal.write("\u{07}\u{1B}]2;hello\u{07}\u{1B}[?2026hx\u{1B}[?2026l")
        #expect(recorder.events == ["bell", "title", "hold", "release"])
        #expect(terminal.title == "hello")
    }

    @Test func eventsAndRepliesWorkTogether() throws {
        let terminal = try makeTerminal()
        let recorder = EventRecorder()
        var reply: [UInt8] = []
        try terminal.setReplyHandler { reply += $0 }
        try terminal.setEventHandler(recorder.handler)
        terminal.write("\u{07}\u{1B}[6n")
        #expect(recorder.events == ["bell"])
        #expect(String(decoding: reply, as: UTF8.self) == "\u{1B}[1;1R")
    }
}
