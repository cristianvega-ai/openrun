import AppKit
import Foundation
import SessionProtocol
import Synchronization
import Testing
@testable import OpenRunApplication

@MainActor @Suite(.serialized) struct ApprovalQuestionAlertsTests {
    private static func question() -> ApprovalQuestion {
        let session = SessionSummary(identifier: UUID(), folder: "/", command: ["sh"], size: SessionSize(columns: 80, rows: 24), createdAt: .now)
        return ApprovalQuestion(identifier: UUID(), askingSession: session, targetSession: session, request: .read)
    }

    private static func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func eachQuestionShowsAloneAndItsButtonIsTheAnswer() async {
        _ = NSApplication.shared
        let answers = Mutex<[String]>([])
        var titles: [String] = []
        let first = Self.question()
        let second = Self.question()
        let alerts = ApprovalQuestionAlerts(answer: { identifier, allows in
            answers.withLock { $0.append("\(identifier == first.identifier ? "first" : "second") \(allows)") }
        }, runModal: { alert in
            titles.append(alert.buttons.map(\.title).joined(separator: ","))
            return titles.count == 1 ? .alertSecondButtonReturn : .alertFirstButtonReturn
        }, stopModal: { _ in })
        alerts.handle(.question(first))
        alerts.handle(.question(second))
        await Self.waitUntil { answers.withLock { $0.count } == 2 }
        #expect(answers.withLock { $0 } == ["first true", "second false"])
        #expect(titles == ["Don't Allow,Allow", "Don't Allow,Allow"])
    }

    /// A question that ends while it waits or while it shows gets no answer.
    @Test func aQuestionThatEndsGetsNoAnswer() async {
        _ = NSApplication.shared
        let answers = Mutex<[UUID]>([])
        let shown = Self.question()
        let waiting = Self.question()
        var alerts: ApprovalQuestionAlerts!
        var stopped = false
        var shownCount = 0
        alerts = ApprovalQuestionAlerts(answer: { identifier, _ in answers.withLock { $0.append(identifier) } }, runModal: { _ in
            shownCount += 1
            alerts.handle(.ended(waiting.identifier))
            alerts.handle(.ended(shown.identifier))
            return stopped ? .abort : .alertSecondButtonReturn
        }, stopModal: { _ in stopped = true })
        alerts.handle(.question(shown))
        alerts.handle(.question(waiting))
        await Self.waitUntil { shownCount == 1 }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(stopped && shownCount == 1)
        #expect(answers.withLock { $0 }.isEmpty)
    }
}
