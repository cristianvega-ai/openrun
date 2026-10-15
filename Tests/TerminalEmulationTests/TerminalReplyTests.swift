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

    @Test func sizeReportsFollowAResize() throws {
        let (terminal, recorder) = try makeRecordingTerminal()
        try terminal.resize(to: TerminalSize(columns: 100, rows: 40))
        terminal.write("\u{1B}[18t")
        #expect(recorder.text == "\u{1B}[8;40;100t")
    }

    @Test func theColorSchemeQueryGetsOneReplyFromTheCurrentAppearance() throws {
        let (terminal, recorder) = try makeRecordingTerminal()
        terminal.write("\u{1B}[?996n")
        #expect(recorder.replies.count == 1)
        let expected = TerminalColorScheme.current() == .dark ? "\u{1B}[?997;1n" : "\u{1B}[?997;2n"
        #expect(recorder.text == expected)
    }

    @Test func theColorSchemeReplyNamesDarkAndLight() throws {
        for (scheme, expected) in [(TerminalColorScheme.dark, "\u{1B}[?997;1n"), (.light, "\u{1B}[?997;2n")] {
            let terminal = try makeTerminal()
            let recorder = ReplyRecorder()
            try terminal.setReplyHandler({ recorder.replies.append($0) }, colorScheme: { scheme })
            terminal.write("\u{1B}[?996n")
            #expect(recorder.replies.count == 1)
            #expect(recorder.text == expected)
        }
    }

    @Test func theColorSchemeIsReadAtEachQuery() throws {
        let terminal = try makeTerminal()
        let recorder = ReplyRecorder()
        let scheme = SchemeBox()
        try terminal.setReplyHandler({ recorder.replies.append($0) }, colorScheme: { scheme.value })
        terminal.write("\u{1B}[?996n")
        scheme.value = .light
        terminal.write("\u{1B}[?996n")
        #expect(recorder.replies.map { String(decoding: $0, as: UTF8.self) } == ["\u{1B}[?997;1n", "\u{1B}[?997;2n"])
    }

    @Test func removingTheHandlerSilencesSizeAndColorSchemeQueries() throws {
        let (terminal, recorder) = try makeRecordingTerminal()
        try terminal.setReplyHandler(nil)
        terminal.write("\u{1B}[18t\u{1B}[14t\u{1B}[?996n")
        #expect(recorder.replies.isEmpty)
    }

    // MARK: - Colors and pixel size

    private func answers(to query: String, scheme: TerminalColorScheme = .light, columns: UInt16 = 20, rows: UInt16 = 5) throws -> [String] {
        let terminal = try makeTerminal(columns: columns, rows: rows)
        let recorder = ReplyRecorder()
        try terminal.setReplyHandler({ recorder.replies.append($0) }, colorScheme: { scheme })
        terminal.write(query)
        return recorder.replies.map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func foregroundAndBackgroundQueriesAreAnsweredFromTheLightAppearance() throws {
        #expect(try answers(to: "\u{1B}]10;?\u{07}") == ["\u{1B}]10;rgb:0000/0000/0000\u{07}"])
        #expect(try answers(to: "\u{1B}]11;?\u{07}") == ["\u{1B}]11;rgb:ffff/ffff/ffff\u{07}"])
    }

    @Test func foregroundAndBackgroundQueriesAreAnsweredFromTheDarkAppearance() throws {
        #expect(try answers(to: "\u{1B}]10;?\u{07}", scheme: .dark) == ["\u{1B}]10;rgb:ffff/ffff/ffff\u{07}"])
        #expect(try answers(to: "\u{1B}]11;?\u{07}", scheme: .dark) == ["\u{1B}]11;rgb:0000/0000/0000\u{07}"])
    }

    @Test func aColorQueryEndedByStringTerminatorGetsOneReply() throws {
        #expect(try answers(to: "\u{1B}]11;?\u{1B}\\", scheme: .dark) == ["\u{1B}]11;rgb:0000/0000/0000\u{1B}\\"])
    }

    @Test func theColorsFollowTheAppearanceAtEachQuery() throws {
        let terminal = try makeTerminal()
        let recorder = ReplyRecorder()
        let scheme = SchemeBox()
        try terminal.setReplyHandler({ recorder.replies.append($0) }, colorScheme: { scheme.value })
        terminal.write("\u{1B}]11;?\u{07}")
        scheme.value = .light
        terminal.write("\u{1B}]11;?\u{07}")
        #expect(recorder.replies.map { String(decoding: $0, as: UTF8.self) } == ["\u{1B}]11;rgb:0000/0000/0000\u{07}", "\u{1B}]11;rgb:ffff/ffff/ffff\u{07}"])
    }

    @Test func aTerminalWithoutAHandlerStaysSilentForColorAndDotSizeQueries() throws {
        let terminal = try makeTerminal()
        terminal.write("\u{1B}]10;?\u{07}\u{1B}]11;?\u{07}\u{1B}[15t")
        let recorder = ReplyRecorder()
        try terminal.setReplyHandler({ recorder.replies.append($0) })
        try terminal.setReplyHandler(nil)
        terminal.write("\u{1B}]10;?\u{07}\u{1B}]11;?\u{07}\u{1B}[15t")
        #expect(recorder.replies.isEmpty)
    }

    @Test func theScreenSizeInDotsUsesTheNominalCell() throws {
        // 5 rows of 16 pixels and 20 columns of 8 pixels.
        #expect(try answers(to: "\u{1B}[15t") == ["\u{1B}[5;80;160t"])
        #expect(try answers(to: "\u{1B}[15t", columns: 100, rows: 40) == ["\u{1B}[5;640;800t"])
    }

    @Test func theScreenSizeInDotsFollowsAResize() throws {
        let terminal = try makeTerminal()
        let recorder = ReplyRecorder()
        try terminal.setReplyHandler { recorder.replies.append($0) }
        try terminal.resize(to: TerminalSize(columns: 100, rows: 40))
        terminal.write("\u{1B}[15t")
        #expect(recorder.text == "\u{1B}[5;640;800t")
    }

    @Test func aScreenSizeQuerySplitAcrossWritesGetsOneReply() throws {
        let terminal = try makeTerminal()
        let recorder = ReplyRecorder()
        try terminal.setReplyHandler { recorder.replies.append($0) }
        for piece in ["x\u{1B}", "[1", "5", "t", "y"] { terminal.write(piece) }
        #expect(recorder.text == "\u{1B}[5;80;160t")
        #expect(try terminal.visibleText() == "xy")
    }

    @Test func repliesComeInTheOrderOfTheQueries() throws {
        #expect(try answers(to: "\u{1B}[6n\u{1B}[15t\u{1B}[18t\u{1B}[15t") == [
            "\u{1B}[1;1R", "\u{1B}[5;80;160t", "\u{1B}[8;5;20t", "\u{1B}[5;80;160t",
        ])
    }

    @Test func sequencesThatLookLikeTheScreenSizeQueryGetNoReply() throws {
        for text in ["\u{1B}[?15t", "\u{1B}[1;15t", "\u{1B}[115t", "\u{1B}[15u", "\u{1B}[1\u{1B}[5t", "[15t", "\u{1B}[15", "\u{1B}[1\u{18}5t"] {
            #expect(try answers(to: text).isEmpty, "text: \(text.debugDescription)")
        }
    }

    @Test func theQueriesChangeNoPictureOrText() throws {
        // The colors that answer OSC 10 and OSC 11 are a setting of the
        // terminal. What `openrun attach` draws (the visible screen as
        // sequences, from a restored snapshot) and what `openrun read` prints
        // (plain text) must not depend on it. The terminal without a handler
        // is the reference. Each scheme gets the same output in both.
        let escape = "\u{1B}"
        let outputs = [
            "hi \(escape)[31mred\(escape)[0m\r\nthere",
            "\(escape)[38;2;0;0;0mblack\(escape)[48;2;255;255;255mwhite\(escape)[0m",
            "\(escape)[7mreverse\(escape)[0m \(escape)[39;49mdefault",
            "\(escape)]10;rgb:ff/00/00\(escape)\\\(escape)]11;rgb:00/ff/00\(escape)\\ x",
            "\(escape)]10;rgb:ff/00/00\(escape)\\\(escape)]110\(escape)\\ x",
            "\(escape)]11;rgb:00/ff/00\(escape)\\\(escape)]111\(escape)\\ x",
            "\(escape)]4;1;rgb:12/34/56\(escape)\\\(escape)[31mx\(escape)]104\(escape)\\",
            "abc\(escape)c def",
            "\(escape)[?1049hALT\(escape)[7m rev",
            "\(escape)[44m\(escape)[2J\(escape)[K\(escape)[0m",
            "\(escape)]11;?\(escape)\\\(escape)]10;?\(escape)\\\(escape)[15t text",
        ]
        let after = "\(escape)]111\(escape)\\\(escape)[0m more\(escape)[31m"
        for scheme in [TerminalColorScheme.light, .dark] {
            for output in outputs {
                let reference = try makeTerminal()
                let answering = try makeTerminal()
                try answering.setReplyHandler({ _ in }, colorScheme: { scheme })
                let restoredReference = try { () -> Terminal in
                    reference.write(output)
                    return try TerminalSnapshot(capturing: reference).restoreTerminal(scrollbackLimit: 10)
                }()
                answering.write(output)
                let restoredAnswering = try TerminalSnapshot(capturing: answering).restoreTerminal(scrollbackLimit: 10)
                restoredReference.write(after)
                restoredAnswering.write(after)
                for (left, right) in [(reference, answering), (restoredReference, restoredAnswering)] {
                    for format in [ScreenFormat.plainText, .virtualTerminalSequences, .hypertextMarkup] {
                        for extent in [ScreenExtent.visible, .withScrollback] {
                            #expect(
                                try left.formatted(format, extent: extent) == right.formatted(format, extent: extent),
                                "\(scheme) \(format) \(extent): \(output.debugDescription)"
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reading the appearance

    private final class FakeAppearance: Sendable {
        private let state = Mutex((style: String?.none, reads: 0, seconds: 0.0))
        var reads: Int { state.withLock { $0.reads } }
        func set(style: String?) { state.withLock { $0.style = style } }
        func advance(by seconds: Double) { state.withLock { $0.seconds += seconds } }
        func read() -> String? { state.withLock { $0.reads += 1; return $0.style } }
        func now(from start: ContinuousClock.Instant) -> ContinuousClock.Instant {
            start + .seconds(state.withLock { $0.seconds })
        }
    }

    private func makeReader(_ fake: FakeAppearance) -> TerminalColorScheme.AppearanceReader {
        let start = ContinuousClock.now
        return TerminalColorScheme.AppearanceReader(readStyle: { fake.read() }, now: { fake.now(from: start) })
    }

    @Test func theAppearanceIsReadFreshWithinAboutOneSecond() {
        let fake = FakeAppearance()
        let reader = makeReader(fake)
        #expect(reader.scheme() == .light)
        fake.set(style: "Dark")
        fake.advance(by: 1.1)
        #expect(reader.scheme() == .dark)
        fake.set(style: nil)
        fake.advance(by: 1.1)
        #expect(reader.scheme() == .light)
    }

    @Test func theAppearanceIsReadAtMostOnceEachSecond() {
        let fake = FakeAppearance()
        let reader = makeReader(fake)
        _ = reader.scheme()
        fake.set(style: "Dark")
        for _ in 0..<100 {
            fake.advance(by: 0.009)
            #expect(reader.scheme() == .light)
        }
        #expect(fake.reads == 1)
        fake.advance(by: 0.2)
        #expect(reader.scheme() == .dark)
        #expect(fake.reads == 2)
    }

    @Test func aStoredStyleOtherThanDarkMeansLight() {
        let fake = FakeAppearance()
        fake.set(style: "Unknown")
        #expect(makeReader(fake).scheme() == .light)
    }

    @Test func theSystemReaderSeesAChangeMadeByAnotherProcess() throws {
        // A domain of its own, so the real appearance stays as it is.
        let domain = "ai.cristianvega.openrun.tests.appearance-\(UUID().uuidString)"
        func defaults(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = arguments
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }
        defer { try? defaults(["delete", domain]) }
        func style() -> String? {
            TerminalColorScheme.AppearanceReader.readStyle(key: "AppleInterfaceStyle", applicationIdentifier: domain as CFString)
        }
        #expect(style() == nil)
        try defaults(["write", domain, "AppleInterfaceStyle", "Dark"])
        #expect(style() == "Dark")
        try defaults(["delete", domain, "AppleInterfaceStyle"])
        #expect(style() == nil)
    }

    // MARK: - Installing

    @Test func theBoxIsStoredBeforeLibghosttyReceivesItsPointer() throws {
        let terminal = try makeTerminal()
        let box = TerminalReplyBox(handler: { _ in }, colorScheme: { .dark })
        var storedWhenInstalling = false
        try terminal.install(box) { storedWhenInstalling = terminal.replyBox === box }
        #expect(storedWhenInstalling)
        #expect(terminal.hasReplyHandler)
    }
}

private final class SchemeBox: @unchecked Sendable {
    var value = TerminalColorScheme.dark
}
