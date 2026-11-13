import Foundation

/// The words and the choices of a condition of a thread that the chat
/// shows above the composer, such as an account at its limit.
struct ThreadConditionWords: Equatable {
    enum Choice: Equatable {
        case returnFromTerminal
        case openInTerminal
        case newThread(account: String)
    }

    var symbolName: String
    var title: String
    var detail: String?
    var choices: [(title: String, choice: Choice)]

    static func == (left: Self, right: Self) -> Bool {
        (left.symbolName, left.title, left.detail) == (right.symbolName, right.title, right.detail)
            && left.choices.map(\.title) == right.choices.map(\.title) && left.choices.map(\.choice) == right.choices.map(\.choice)
    }

    /// Nil when the thread takes messages as usual.
    init?(_ facts: ChatThreadFacts, now: Date = Date()) {
        switch facts.condition {
        case .ready: return nil
        case .startFailed(let reason, let advice):
            symbolName = "exclamationmark.triangle"
            title = "\(facts.agentName) could not start"
            detail = [reason, advice].filter { !$0.isEmpty }.joined(separator: "\n")
            choices = []
        case .atLimit(let resetTime, let accounts):
            symbolName = "hourglass"
            title = facts.accountName.map { "The \($0) account reached its limit" } ?? "The account reached its limit"
            detail = "The thread goes on when the account resets" + (accounts.isEmpty ? "." : ", or you can go on in a new thread.")
            choices = accounts.map { ("New Thread on \($0.name)", .newThread(account: $0.identifier)) }
        case .notSignedIn(let accounts):
            symbolName = "person.crop.circle.badge.exclamationmark"
            title = facts.accountName.map { "\(facts.agentName) is not signed in on the \($0) account" } ?? "\(facts.agentName) is not signed in"
            detail = "Open the conversation in a terminal and sign in there. Then come back and send your message again."
                + (accounts.isEmpty ? " You can also add another login in Settings, in the Accounts pane." : " Or go on in a new thread under another account.")
            choices = [("Open in Terminal", .openInTerminal)] + accounts.map { ("New Thread on \($0.name)", .newThread(account: $0.identifier)) }
        case .openInTerminal:
            symbolName = "terminal"
            title = "This conversation is open in a terminal"
            detail = "The chat shows it, but takes no messages until you come back."
            choices = [("Back to Chat", .returnFromTerminal)]
        }
    }

    /// "at 3:40 PM" today, or with the day at a later date.
    static func time(_ date: Date, now: Date) -> String {
        let isToday = Calendar.current.isDate(date, inSameDayAs: now)
        let text = date.formatted(isToday ? .dateTime.hour().minute() : .dateTime.weekday(.wide).hour().minute())
        return "at " + text
    }
}
