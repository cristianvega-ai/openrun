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
}
