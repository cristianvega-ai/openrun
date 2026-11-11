import Foundation
import Testing
@testable import SessionProtocol

@Suite struct SessionFactsTests {
    private static let identifier = UUID(uuidString: "3F2A9C1E-0000-4000-8000-000000000001")!

    private static func summary() -> SessionSummary {
        SessionSummary(identifier: identifier, folder: "/work", command: ["/bin/zsh"], size: SessionSize(columns: 80, rows: 24), createdAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// A session process from before the facts sends none of them.
    @Test func anOlderSummaryDecodesWithNoFacts() throws {
        let older = #"{"sessionList":{"_0":[{"identifier":"3F2A9C1E-0000-4000-8000-000000000001","folder":"/work","command":["/bin/zsh"],"size":{"columns":80,"rows":24},"createdAt":1700000000}]}}"#
        let message = try ServerMessage(frame: MessageFrame(kind: .control, payload: Data(older.utf8)))
        #expect(message == .sessionList([Self.summary()]))
        guard case .sessionList(let summaries) = message, let decoded = summaries.first else { return }
        #expect(decoded.name == nil && decoded.title == nil && decoded.isInProgress == nil && decoded.alert == nil)
    }

    @Test func everyFactSurvivesEncodingAndDecoding() throws {
        var summary = Self.summary()
        summary.name = "build"
        summary.title = "make all"
        summary.currentFolder = "/work/sub"
        summary.branch = "main"
        summary.foregroundProgram = "make"
        summary.isInProgress = true
        summary.lastOutputAt = Date(timeIntervalSince1970: 1_700_000_010)
        summary.lastInputAt = Date(timeIntervalSince1970: 1_700_000_005)
        summary.alert = SessionAlert(text: "done", raisedAt: Date(timeIntervalSince1970: 1_700_000_020), source: .terminalNotification)
        let frame = try ServerMessage.sessionCreated(summary).frame()
        #expect(try ServerMessage(frame: frame) == .sessionCreated(summary))
        let text = String(decoding: frame.payload, as: UTF8.self)
        for key in ["\"name\"", "\"title\"", "\"currentFolder\"", "\"branch\"", "\"foregroundProgram\"", "\"isInProgress\"", "\"lastOutputAt\"", "\"lastInputAt\"", "\"terminalNotification\""] {
            #expect(text.contains(key), "\(text)")
        }
    }

    /// A summary without facts has the text of the document, so an older
    /// client reads it as before.
    @Test func aSummaryWithoutFactsSendsNoNewField() throws {
        let text = String(decoding: try ServerMessage.attached(Self.summary()).frame().payload, as: UTF8.self)
        #expect(!text.contains("isInProgress") && !text.contains("alert") && !text.contains("name"))
    }

    @Test func aTextLosesItsControlCharactersAndKeepsAtMostTheLimit() {
        #expect(SessionSummary.boundedText("a\u{1B}]2;x\u{07}b\u{9B}c\td") == "a]2;xbcd")
        let long = String(repeating: "é", count: SessionSummary.textLimit + 10)
        #expect(SessionSummary.boundedText(long).unicodeScalars.count == SessionSummary.textLimit)
        // One character with many combining marks counts each scalar.
        let marked = "a" + String(repeating: "\u{301}", count: 100_000)
        #expect(SessionSummary.boundedText(marked).unicodeScalars.count == SessionSummary.textLimit)
    }

    @Test func anAlertBoundsItsText() {
        let alert = SessionAlert(text: "\u{1B}[31m" + String(repeating: "x", count: 1000), raisedAt: .now, source: .notifyCommand)
        #expect(alert.text == "[31m" + String(repeating: "x", count: SessionSummary.textLimit - 4))
    }
}
