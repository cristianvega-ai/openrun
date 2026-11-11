import Testing

@testable import ChatView

@MainActor struct ThreadConditionViewTests {
    @Test func aChoiceGoesToTheAction() throws {
        let facts = ChatThreadFacts(threadIdentifier: "t", title: "T", agentName: "Codex", condition: .atLimit(resetTime: nil, otherAccounts: [
            ChatAccount(identifier: "a", name: "A"), ChatAccount(identifier: "b", name: "B"),
        ]))
        let view = ThreadConditionView()
        view.show(try #require(ThreadConditionWords(facts)), palette: ChatPalette(appearance: .graphite))
        var chosen: [ThreadConditionWords.Choice] = []
        view.choiceAction = { chosen.append($0) }
        view.buttons[1].performClick(nil)
        #expect(chosen == [.newThread(account: "b")])
        #expect(view.height(forWidth: 320) >= view.height(forWidth: 700))
        #expect(view.accessibilityLabel() == "The account reached its limit")
    }
}
