import AppKit
import Metal
import Testing
import TerminalEmulation
import TerminalRendering
import TerminalTheme
@testable import TerminalView

@Suite struct AppearanceObserverTests {
    @Test func theObserverTellsOnlyAChangeOfTheScheme() throws {
        let dark = try #require(NSAppearance(named: .darkAqua))
        let light = try #require(NSAppearance(named: .aqua))
        var observer = AppearanceObserver(appearance: dark)
        #expect(observer.scheme == .dark)
        let sameScheme = observer.observe(dark)
        let newScheme = observer.observe(light)
        #expect(!sameScheme)
        #expect(newScheme)
        #expect(observer.scheme == .light)
    }
}

@MainActor @Suite struct AppearanceOfViewTests {
    /// Draws the view and gives the color of a pixel in the space around the grid.
    private func corner(of view: TerminalView) throws -> TerminalColor {
        let size = view.renderer.pixelSize(for: view.gridSize)
        let target = try OffscreenTarget(device: #require(MTLCreateSystemDefaultDevice()), width: size.width, height: size.height)
        try view.drawFrame(into: target)
        return target.pixel(horizontalPosition: 0, verticalPosition: 0)
    }

    @Test func theViewFollowsTheAppearanceWithTheGraphiteTheme() throws {
        let view = try TerminalView()
        view.appearance = NSAppearance(named: .darkAqua)
        #expect(try corner(of: view) == TerminalTheme.graphite(for: .dark).background)
        #expect(view.terminal.defaultForegroundColor == TerminalTheme.graphite(for: .dark).foreground)
        view.appearance = NSAppearance(named: .aqua)
        #expect(try corner(of: view) == TerminalTheme.graphite(for: .light).background)
        #expect(view.renderer.selectionColor == TerminalTheme.graphite(for: .light).selection)
    }
}
