import AccountUsage
import AppKit
import Testing
@testable import ProjectsList

@MainActor @Suite struct AccountUsageViewTests {
    @Test func theFootShowsEachWindowOfAnAccountWithTheTimeOfTheReading() {
        let reading = AccountUsageDisplay(
            title: "Claude Code · Work", windows: [.init(name: "5 h", usedFraction: 0.124), .init(name: "Week", usedFraction: 1, isAtLimit: true)],
            readTime: "14:32", help: "Week 100% used, resets Thursday at 09:00.")
        let foot = AccountUsageView()
        #expect(foot.isHidden)
        foot.show([reading])
        #expect(!foot.isHidden && foot.descendants(NSTextField.self).map(\.stringValue) == ["Claude Code · Work", "14:32", "5 h", "12%", "Week", "100%"])
        #expect(foot.descendants(UsageMeterView.self).map(\.isAtLimit) == [false, true])
        #expect(foot.descendants(NSStackView.self).contains { $0.toolTip == reading.help && $0.accessibilityLabel() == reading.help })
        foot.show([])
        #expect(foot.isHidden && foot.descendants(NSTextField.self).isEmpty)
    }
}
