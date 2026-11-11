import Testing

@testable import ChatView

@MainActor struct JumpToNewestButtonTests {
    @Test func theButtonRunsItsActionAndTheEmptyThreadNamesTheAgent() {
        let button = JumpToNewestButton()
        var presses = 0
        button.action = { presses += 1 }
        #expect(button.accessibilityPerformPress())
        #expect(presses == 1)
        let empty = EmptyThreadView()
        empty.show(agentName: "Codex", palette: ChatPalette(appearance: .graphite))
        #expect(empty.title.stringValue == "Codex")
    }
}
