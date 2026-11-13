import Foundation
import Testing

@testable import ChatView

struct ThreadConditionWordsTests {
    func facts(_ condition: ChatThreadCondition) -> ChatThreadFacts {
        ChatThreadFacts(threadIdentifier: "t", title: "T", agentName: "Claude Code", accountName: "Work", condition: condition)
    }

    @Test func aReadyThreadHasNoWords() {
        #expect(ThreadConditionWords(facts(.ready)) == nil)
    }

    @Test func aFailedStartSaysWhyAndWhatToDo() {
        let words = ThreadConditionWords(facts(.startFailed(reason: "claude was not found.", advice: "Install Claude Code.")))
        #expect(words?.title == "Claude Code could not start")
        #expect(words?.detail == "claude was not found.\nInstall Claude Code.")
    }

    @Test func aLimitOffersTheOtherAccounts() {
        let now = Date()
        let words = ThreadConditionWords(facts(.atLimit(resetTime: now.addingTimeInterval(60), otherAccounts: [
            ChatAccount(identifier: "personal", name: "Personal"),
        ])), now: now)
        #expect(words?.title == "The Work account reached its limit")
        // The composer shows the time of the reset, so the box does not.
        #expect(words?.detail == "The thread goes on when the account resets, or you can go on in a new thread.")
        #expect(words?.choices.map(\.title) == ["New Thread on Personal"])
        #expect(words?.choices.map(\.choice) == [.newThread(account: "personal")])
    }

    @Test func aThreadWithNoLoginOffersTheTerminalAndTheOtherAccounts() {
        let words = ThreadConditionWords(facts(.notSignedIn(otherAccounts: [ChatAccount(identifier: "", name: "the Account of Your Shell")])))
        #expect(words?.title == "Claude Code is not signed in on the Work account")
        #expect(words?.detail?.hasSuffix("Or go on in a new thread under another account.") == true)
        #expect(words?.choices.map(\.title) == ["Open in Terminal", "New Thread on the Account of Your Shell"])
        #expect(words?.choices.map(\.choice) == [.openInTerminal, .newThread(account: "")])
        // With no other account, the box tells where to add one.
        let alone = ThreadConditionWords(ChatThreadFacts(threadIdentifier: "t", title: "T", agentName: "Codex", condition: .notSignedIn(otherAccounts: [])))
        #expect(alone?.title == "Codex is not signed in" && alone?.detail?.contains("in the Accounts pane") == true && alone?.choices.count == 1)
    }

    @Test func aTerminalThreadOffersTheWayBack() {
        #expect(ThreadConditionWords(facts(.openInTerminal))?.choices.map(\.choice) == [.returnFromTerminal])
    }
}
