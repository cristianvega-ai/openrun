import Testing
import TerminalTheme
@testable import ChatView

struct ChatAppearanceTests {
    @Test func theGraphiteColorsComeFromTheTerminalTheme() {
        let light = ChatAppearance.graphite.light
        #expect(light.background == ChatColor(red: 250 / 255, green: 251 / 255, blue: 252 / 255))
        #expect(light.text == ChatColor(red: 30 / 255, green: 32 / 255, blue: 34 / 255))
        #expect(light.attention == ChatColor(TerminalTheme.graphite(for: .light).firstSixteenColors[1]))
        #expect(ChatAppearance.graphite.dark.background == ChatColor(TerminalTheme.graphite(for: .dark).background))
        #expect(ChatAppearance.graphite.bodyFontSize == 14)
    }

    @Test func quietFillsLieBetweenTheBackgroundAndTheText() {
        for colors in [ChatAppearance.graphite.light, ChatAppearance.graphite.dark] {
            let distance = { (color: ChatColor) in abs(color.red - colors.background.red) }
            #expect(distance(colors.codeBackground) < distance(colors.userMessageBackground))
            #expect(distance(colors.userMessageBackground) < distance(colors.divider))
            #expect(distance(colors.divider) < distance(colors.text))
        }
    }

    @Test func aMixMovesEachComponent() {
        let black = ChatColor(red: 0, green: 0, blue: 0)
        let white = ChatColor(red: 1, green: 1, blue: 1, alpha: 0)
        #expect(black.mixed(with: white, fraction: 0.25) == ChatColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 0.75))
        #expect(black.withAlpha(0.5).alpha == 0.5)
    }
}
