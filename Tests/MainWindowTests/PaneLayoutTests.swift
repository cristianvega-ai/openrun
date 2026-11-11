import Foundation
import Testing
@testable import MainWindow

@Suite struct PaneLayoutTests {
    private func temporaryDefaults() throws -> UserDefaults {
        let name = "PaneLayoutTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theLayoutComesBackAsTheUserLeftIt() throws {
        let defaults = try temporaryDefaults()
        #expect(PaneLayout.load(from: defaults) == PaneLayout())
        var layout = PaneLayout()
        (layout.projectsWidth, layout.sessionsWidth, layout.projectsHidden) = (250, 340, true)
        layout.save(to: defaults)
        #expect(PaneLayout.load(from: defaults) == layout)
        defaults.set(Data("not a layout".utf8), forKey: PaneLayout.defaultsKey)
        #expect(PaneLayout.load(from: defaults) == PaneLayout())
    }

    @Test func eachWidthStaysInsideItsLimits() {
        var layout = PaneLayout()
        (layout.projectsWidth, layout.sessionsWidth) = (20, 2_000)
        #expect(layout.clamped().projectsWidth == 160 && layout.clamped().sessionsWidth == 520)
    }

    @Test func theNarrowestWindowHoldsTheVisibleListsAndTheContent() {
        var layout = PaneLayout()
        #expect(layout.minimumWidth(content: 500) == 900)
        layout.projectsHidden = true
        #expect(layout.minimumWidth(content: 500) == 740)
        layout.sessionsHidden = true
        #expect(layout.minimumWidth(content: 500) == 500)
    }
}
