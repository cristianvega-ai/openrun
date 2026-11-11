import AppKit
import Testing
@testable import MainWindow

@MainActor @Suite struct SheetShadowViewTests {
    @Test func theShadowTakesNoClicksAndIsStrongerInTheDark() throws {
        let shadow = SheetShadowView()
        #expect(shadow.hitTest(NSPoint(x: 5, y: 5)) == nil)
        shadow.appearance = NSAppearance(named: .aqua)
        shadow.updateLayer()
        let light = shadow.edgeOpacity
        shadow.appearance = NSAppearance(named: .darkAqua)
        shadow.updateLayer()
        #expect(light > 0 && shadow.edgeOpacity > light)
    }

    /// In the dark the shadow must read as an edge, and it fades with a
    /// curve, so it has no hard line.
    @Test func theDarkShadowReadsAsASoftEdge() {
        let shadow = SheetShadowView()
        shadow.appearance = NSAppearance(named: .darkAqua)
        shadow.updateLayer()
        #expect(shadow.edgeOpacity >= 0.45 && SheetShadowView.width >= 14)
        let middle = shadow.opacity(at: 0.5)
        #expect(middle > 0 && middle < shadow.edgeOpacity / 3)
    }
}
