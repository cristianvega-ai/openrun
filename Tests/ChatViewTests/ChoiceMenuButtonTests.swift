import AppKit
import Testing

@testable import ChatView

@MainActor struct ChoiceMenuButtonTests {
    @Test func theMenuChecksThePresentChoiceAndReportsANewOne() {
        let button = ChoiceMenuButton(label: "Model")
        let opus = ChatChoice(identifier: "opus", title: "Opus 5.5")
        button.show([opus, ChatChoice(identifier: "sonnet", title: "Sonnet 5.5")], current: opus, palette: ChatPalette(appearance: .graphite))
        #expect(button.title == "Opus 5.5")
        #expect(button.accessibilityValue() as? String == "Opus 5.5")
        var chosen: [String] = []
        button.selectAction = { chosen.append($0.identifier) }
        let menu = button.makeMenu()
        #expect(menu.items.map(\.state) == [.on, .off])
        button.choose(menu.items[1])
        #expect(chosen == ["sonnet"])
    }
}
