import AccountUsage
import AppKit
import Testing
@testable import SettingsWindow

/// The usage of one account in the Accounts pane.
@MainActor @Suite struct AccountUsageLineViewTests {
    private func texts(_ line: AccountUsageLineView) -> [String] {
        line.arrangedSubviews.map { ($0 as? NSTextField)?.stringValue ?? "meter" }
    }

    @Test func aLineShowsEachWindowAndTheTimeOfTheReading() {
        let line = AccountUsageLineView()
        // OpenRun sends no request only to read the usage, so an account can have no reading.
        #expect(texts(line) == ["No usage yet. A thread of this account reads it."] && line.toolTip == nil)
        let reading = AccountUsageDisplay(
            title: "Claude Code", windows: [.init(name: "5h", usedFraction: 0.124), .init(name: "Week", usedFraction: 1, isAtLimit: true)],
            readTime: "14:32", help: "Claude Code: 5h 12% used.")
        line.show(reading)
        #expect(texts(line) == ["5h", "meter", "12%", "Week", "meter", "100%", "Read at 14:32"] && line.toolTip == reading.help)
        #expect((line.arrangedSubviews[4] as? UsageMeterView)?.isAtLimit == true)
        line.show(nil)
        #expect(texts(line).count == 1 && line.display == nil)
    }
}
