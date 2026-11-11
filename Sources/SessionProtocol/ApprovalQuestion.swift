import Foundation

/// A question that the session process asks the user through the app,
/// before a program in one session acts on another session (decisions of
/// 2026-10-15 and 2026-11-10).
public struct ApprovalQuestion: Codable, Equatable, Sendable {
    /// What the program asks to do to the target session.
    public enum Request: Codable, Equatable, Sendable {
        /// Type text. The question holds only its start, because the text
        /// can be as large as a frame. Both count Unicode scalars: one
        /// character can hold any number of combining marks.
        case type(start: String, characterCount: Int)
        case read
        case attach
        case kill
    }

    /// The most Unicode scalars of typed text that a question shows.
    public static let shownCharacterLimit = 500

    /// The answer names the question by this, so an answer can never apply
    /// to another question.
    public var identifier: UUID
    /// The session of the program that asks.
    public var askingSession: SessionSummary
    public var targetSession: SessionSummary
    public var request: Request

    public init(identifier: UUID, askingSession: SessionSummary, targetSession: SessionSummary, request: Request) {
        self.identifier = identifier
        self.askingSession = askingSession
        self.targetSession = targetSession
        self.request = request
    }
}

extension ApprovalQuestion.Request {
    /// A request to type the text, with the start that a question shows.
    public static func typing(_ text: String) -> Self {
        var start = String.UnicodeScalarView()
        start.append(contentsOf: text.unicodeScalars.prefix(ApprovalQuestion.shownCharacterLimit))
        return .type(start: String(start), characterCount: text.unicodeScalars.count)
    }
}
