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

    @Test(arguments: [false, true])
    func aRestoredViewUsesItsAppearanceAndKeepsProgramColors(hasProgramColors: Bool) throws {
        _ = NSApplication.shared
        let applicationScheme = AppearanceObserver.scheme(of: NSApp.effectiveAppearance)
        let snapshotTheme = TerminalTheme.graphite(for: applicationScheme == .dark ? .light : .dark)
        let original = try Terminal(size: TerminalSize(columns: 20, rows: 4), scrollbackLimit: 10)
        try snapshotTheme.apply(to: original)
        if hasProgramColors { original.write("\u{1B}]11;rgb:12/34/56\u{07}\u{1B}]4;2;rgb:65/43/21\u{07}") }
        let view = try TerminalView(restoring: TerminalSnapshot(capturing: original))
        let initial = TerminalTheme.graphite(for: AppearanceObserver.scheme(of: view.effectiveAppearance))
        #expect(initial.background != snapshotTheme.background && view.terminal.defaultBackgroundColor == initial.background)
        let state = try RenderState()
        let customBackground = TerminalColor(red: 0x12, green: 0x34, blue: 0x56)
        let customPalette = TerminalColor(red: 0x65, green: 0x43, blue: 0x21)
        try state.update(from: view.terminal)
        #expect(state.colors.background == (hasProgramColors ? customBackground : initial.background))
        #expect(state.colors.palette[2] == (hasProgramColors ? customPalette : initial.firstSixteenColors[2]))
        view.appearance = NSAppearance(named: .darkAqua)
        let dark = TerminalTheme.graphite(for: .dark)
        #expect(view.terminal.defaultBackgroundColor == dark.background)
        try state.update(from: view.terminal)
        #expect(state.colors.background == (hasProgramColors ? customBackground : dark.background))
        #expect(state.colors.palette[2] == (hasProgramColors ? customPalette : dark.firstSixteenColors[2]))
        view.terminal.write("\u{1B}]111\u{07}\u{1B}]104;2\u{07}")
        try state.update(from: view.terminal)
        #expect(state.colors.background == dark.background && state.colors.palette[2] == dark.firstSixteenColors[2])
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
