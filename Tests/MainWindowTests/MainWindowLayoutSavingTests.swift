import AppKit
import Testing
@testable import MainWindow

/// Defaults that count their writes.
final class CountingDefaults: UserDefaults, @unchecked Sendable {
    var writes = 0

    override func set(_ value: Any?, forKey defaultName: String) {
        writes += 1
        super.set(value, forKey: defaultName)
    }
}

/// The window saves the layout once for each change of the panes, not at
/// each step of an animation or a drag.
@MainActor @Suite(.serialized) struct MainWindowLayoutSavingTests {
    private func makeDefaults() throws -> CountingDefaults {
        let name = "MainWindowTests-\(UUID().uuidString)"
        let defaults = try #require(CountingDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// The completion of an animation runs only when the test lets go of the
    /// main queue, and under load it comes late, so the wait has a condition.
    private func turns(seconds: Double, until condition: () -> Bool = { false }) async {
        let end = Date().addingTimeInterval(seconds)
        while !condition(), Date() < end {
            runLoopTurn()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func runLoopTurn() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    @Test func anAnimatedToggleSavesOnce() async throws {
        let defaults = try makeDefaults()
        let controller = makeMainWindow(defaults: defaults)
        defer { controller.window.close() }
        controller.reducesMotion = { false }
        controller.showWindow()
        let before = defaults.writes
        controller.toggleSessionsList(nil)
        await turns(seconds: 20) { defaults.writes > before }
        await turns(seconds: 0.5)
        #expect(defaults.writes == before + 1)
        #expect(PaneLayout.load(from: defaults).sessionsHidden)
    }

    @Test func aDragSavesOnce() throws {
        let defaults = try makeDefaults()
        let controller = makeMainWindow(defaults: defaults)
        defer { controller.window.close() }
        controller.showWindow()
        let before = defaults.writes
        try dragSessionsEdge(of: controller, by: 60)
        #expect(defaults.writes == before + 1)
        #expect(abs(PaneLayout.load(from: defaults).sessionsWidth - 360) < 2)
    }
}
