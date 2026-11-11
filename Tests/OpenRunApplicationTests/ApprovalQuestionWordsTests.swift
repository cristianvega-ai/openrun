import Foundation
import SessionProtocol
import Testing
@testable import OpenRunApplication

@Suite struct ApprovalQuestionWordsTests {
    private static func session(_ folder: String, _ program: String) -> SessionSummary {
        SessionSummary(identifier: UUID(), folder: folder, command: [program], size: SessionSize(columns: 80, rows: 24), createdAt: .now)
    }

    @Test func theQuestionNamesBothSessionsAndShowsTheText() {
        let asking = Self.session("/work/api", "/usr/local/bin/claude")
        let target = Self.session("/work/web", "/opt/homebrew/bin/codex")
        let words = ApprovalQuestionWords(ApprovalQuestion(identifier: UUID(), askingSession: asking, targetSession: target, request: .typing("yes\r")))
        #expect(words.buttons == ["Don't Allow", "Allow"])
        #expect(words.message.contains("claude in “api” (\(asking.identifierText.prefix(8)))"))
        #expect(words.message.contains("codex in “web” (\(target.identifierText.prefix(8)))"))
        #expect(words.message.contains("yes⏎"))
        #expect(!words.message.contains("first"))
    }

    /// A Return, an escape or another control character must not hide in
    /// the text that the user allows.
    @Test func controlCharactersAreVisible() {
        #expect(ApprovalQuestionWords.visible("a\r\n\t\u{1B}[A\u{3}\u{7F}é") == "a⏎␤⇥⎋[A^C⌫é")
    }

    @Test func longTextSaysHowMuchItLeavesOut() {
        let asking = Self.session("/a", "sh")
        let text = String(repeating: "x", count: ApprovalQuestion.shownCharacterLimit + 10)
        let words = ApprovalQuestionWords(ApprovalQuestion(identifier: UUID(), askingSession: asking, targetSession: asking, request: .typing(text)))
        #expect(words.message.contains("the first \(ApprovalQuestion.shownCharacterLimit) of \(text.count) characters"))
    }

    @Test(arguments: [ApprovalQuestion.Request.read, .attach, .kill]) func eachRequestHasItsOwnTitle(request: ApprovalQuestion.Request) {
        let asking = Self.session("/a", "sh")
        let words = ApprovalQuestionWords(ApprovalQuestion(identifier: UUID(), askingSession: asking, targetSession: asking, request: request))
        #expect(words.title.hasPrefix("Allow a program to"))
        #expect(words.message.contains("one agent must not drive another"))
    }
}
