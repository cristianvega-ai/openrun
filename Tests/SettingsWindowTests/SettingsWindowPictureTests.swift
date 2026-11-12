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
        let tabs = try #require(window.contentViewController as? NSTabViewController)
        for index in tabs.tabViewItems.indices {
            tabs.selectedTabViewItemIndex = index
            let end = Date().addingTimeInterval(0.5)
            while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            let view = try #require(window.contentView)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let name = "settings-\(tabs.tabViewItems[index].label.lowercased()).png"
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appending(path: name))
        }
    }
}
