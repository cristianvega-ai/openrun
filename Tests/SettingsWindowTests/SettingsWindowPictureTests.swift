import AccountUsage
import AppKit
import Settings
import Testing
@testable import SettingsWindow

/// Opt in with OPENRUN_RENDER_OUTPUT to save a picture of each pane of
/// the settings window. The pictures are drawn into a bitmap, so they
/// work while the screen is locked.
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"] != nil))
struct SettingsWindowPictureTests {
    @Test func eachPaneOfTheSettingsWindow() throws {
        let output = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["OPENRUN_RENDER_OUTPUT"]))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let titles = ["plan": "Plan Only", "dontAsk": "Rules Only", "default": "Ask First", "acceptEdits": "Accept Edits", "auto": "Auto"]
        let controller = SettingsWindowController { titles[$0] ?? $0 }
        let values = SettingValues()
        controller.show(Dictionary(uniqueKeysWithValues: SettingName.allCases.map { ($0.rawValue, values.text(of: $0)) }))
        let window = try #require(controller.window)
        defer { window.close() }
        window.orderFrontRegardless()
        let accounts = #"[{"folder":"/Users/ana/.claude-work","name":"Work"},{"folder":"/Users/ana/.claude-home","name":"Home"}]"#
        controller.show(["claude-code-accounts": accounts])
        controller.showUsage([
            AccountUsageDisplay(title: "", windows: [.init(name: "5h", usedFraction: 0.12), .init(name: "Week", usedFraction: 0.38)], readTime: "14:32", help: "", agent: "claude-code"),
            AccountUsageDisplay(title: "", windows: [.init(name: "5h", usedFraction: 1, isAtLimit: true)], readTime: "Nov 12", help: "", agent: "claude-code", account: "Work"),
        ])
        for (index, pane) in controller.panes.enumerated() {
            controller.sidebar.select(pane: index)
            try save(window, as: "settings-\(pane.pane.title.lowercased().replacingOccurrences(of: " ", with: "-")).png", in: output)
        }
        controller.sidebar.searchField.stringValue = "new thread"
        controller.sidebar.search()
        try save(window, as: "settings-search.png", in: output)
        window.appearance = NSAppearance(named: .darkAqua)
        for index in [2, 3] {
            controller.sidebar.select(pane: index)
            try save(window, as: "settings-dark-\(index).png", in: output)
        }
    }

    private func save(_ window: NSWindow, as name: String, in output: URL) throws {
        let end = Date().addingTimeInterval(0.3)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        let view = try #require(window.contentView)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appending(path: name))
    }
}
