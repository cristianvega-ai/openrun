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
        #expect(words?.detail?.hasPrefix("It resets at ") == true)
        #expect(words?.choices.map(\.title) == ["New Thread on Personal"])
        #expect(words?.choices.map(\.choice) == [.newThread(account: "personal")])
    }

    @Test func aTerminalThreadOffersTheWayBack() {
        #expect(ThreadConditionWords(facts(.openInTerminal))?.choices.map(\.choice) == [.returnFromTerminal])
    }
}
