import Testing
@testable import TerminalEmulation

private final class EventRecorder {
    var events: [String] = []
    var handler: TerminalEventHandler {
        TerminalEventHandler(
            bell: { self.events.append("bell") },
            titleChanged: { self.events.append("title") },
            renderHold: { self.events.append($0 ? "hold" : "release") },
            desktopNotification: { self.events.append("notify[\($0)|\($1)]") }
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

    /// libghostty-vt reports OSC 9 and OSC 777, and takes the commands of
    /// ConEmu that share OSC 9, such as the progress report, as their own.
    /// It parses OSC 99 and reports nothing for it.
    @Test func reportsTheNotificationsOfOperatingSystemCommands() throws {
        let terminal = try makeTerminal()
        let recorder = EventRecorder()
        try terminal.setEventHandler(recorder.handler)
        terminal.write("\u{1B}]9;Build done\u{07}")
        terminal.write("\u{1B}]777;notify;Claude Code;Waiting for input\u{1B}\\")
        terminal.write("\u{1B}]9;4;1;50\u{07}\u{1B}]9;4;0\u{07}\u{1B}]9;1;100\u{07}")
        terminal.write("\u{1B}]99;;Hello from kitty\u{1B}\\")
        #expect(recorder.events == ["notify[|Build done]", "notify[Claude Code|Waiting for input]"])
    }

    /// libghostty-vt keeps about 2 KiB of an operating system command and
    /// drops a longer one, so a notification stays within the limit.
    @Test func aNotificationStaysWithinTheLimit() throws {
        let terminal = try makeTerminal()
        var bodies: [String] = []
        try terminal.setEventHandler(TerminalEventHandler(bell: {}, titleChanged: {}, renderHold: { _ in }, desktopNotification: { bodies.append($1) }))
        terminal.write("\u{1B}]9;" + String(repeating: "x", count: 2_000) + "\u{07}")
        terminal.write("\u{1B}]9;" + String(repeating: "y", count: 100_000) + "\u{07}")
        #expect(bodies.map(\.utf8.count) == [2_000])
        #expect(2_000 <= TerminalEventHandler.notificationByteLimit)
    }
}
