import AppKit
import Testing
@testable import PaneAppearance

@MainActor @Suite struct PaneTopRowTests {
    /// A window like the main window: its content fills the whole window,
    /// under a title bar that draws nothing.
    private func makeWindow(holding row: PaneTopRow) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        (window.titlebarAppearsTransparent, window.titleVisibility) = (true, .hidden)
        window.toolbar = NSToolbar(identifier: "PaneTopRowTests")
        window.toolbarStyle = .unified
        row.frame = NSRect(x: 0, y: 300 - PaneTopRow.height, width: 400, height: PaneTopRow.height)
        window.contentView?.addSubview(row)
        row.layoutSubtreeIfNeeded()
        return window
    }

    /// The title bar lies over the row, so a click goes the path of the
    /// frame view of the window, not only of the content view.
    @Test func aButtonInTheRowTakesClicksThroughTheTitleBar() throws {
        let row = PaneTopRow(background: PaneColor.firstPane)
        let button = PaneButton.make(symbol: "plus", label: "Add", target: nil, action: nil)
        row.trailingItems.addArrangedSubview(button)
        let window = makeWindow(holding: row)
        defer { window.close() }
        let frameView = try #require(window.contentView?.superview)
        let middle = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        #expect(frameView.hitTest(frameView.convert(middle, from: nil)) === button)
        let empty = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        #expect(frameView.hitTest(frameView.convert(empty, from: nil)) === row && row.mouseDownCanMoveWindow)
    }

    @Test func theRowHasTheHeightOfTheToolbarAndCentersItsControls() {
        let row = PaneTopRow(background: PaneColor.secondPane)
        let button = PaneButton.make(symbol: "plus", label: "Add", target: nil, action: nil)
        row.leadingItems.addArrangedSubview(button)
        let window = makeWindow(holding: row)
        defer { window.close() }
        // AppKit lays a button out by its alignment rectangle, which is the frame without the bezel insets.
        let alignment = row.leadingItems.convert(button.alignmentRect(forFrame: button.frame), to: row)
        #expect(row.frame.height == 52 && alignment.midY == row.bounds.midY)
        let close = window.standardWindowButton(.closeButton)
        #expect(close.map { $0.convert($0.bounds, to: nil).midY } == row.convert(row.bounds, to: nil).midY)
    }

    @Test func aSymbolButtonHasNoBorderAQuietColorAndAName() {
        let button = PaneButton.make(symbol: "folder.badge.plus", label: "Add Project", target: nil, action: nil)
        #expect(!button.isBordered && button.contentTintColor == PaneColor.quietText)
        #expect(button.accessibilityLabel() == "Add Project" && button.toolTip == "Add Project")
    }

    /// A dirty rectangle can be larger than the row. The row must leave the
    /// rest alone, or it hides the list under it.
    @Test func theRowPaintsOnlyItsOwnBounds() throws {
        let row = PaneTopRow(background: .black)
        row.frame = NSRect(x: 0, y: 0, width: 20, height: PaneTopRow.height)
        let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 20, pixelsHigh: 104, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
        row.draw(NSRect(x: 0, y: 0, width: 20, height: 104))
        NSGraphicsContext.restoreGraphicsState()
        #expect(image.colorAt(x: 10, y: 90)?.alphaComponent == 1)
        #expect(image.colorAt(x: 10, y: 10)?.alphaComponent == 0)
    }
}
