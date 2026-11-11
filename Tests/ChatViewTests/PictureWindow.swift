import AppKit
import Testing
@testable import ChatView

/// A window that holds a chat as the third pane of the main window does,
/// with a top row, for pictures.
@MainActor final class PictureWindow {
    let window: NSWindow
    let controller: ChatViewController

    init(controller: ChatViewController, size: NSSize, appearance: NSAppearance.Name) {
        self.controller = controller
        window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size), styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        let content = PictureBackgroundView(frame: NSRect(origin: .zero, size: size))
        content.color = controller.context.palette.background
        let topRow = NSView(frame: NSRect(x: 0, y: size.height - 52, width: size.width, height: 52))
        let title = NSTextField(labelWithString: controller.paneTitle)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        var right = size.width - 16
        for item in controller.topRowItems.reversed() {
            item.layoutSubtreeIfNeeded()
            let itemSize = item.fittingSize
            right -= itemSize.width
            item.frame = NSRect(x: right, y: (52 - itemSize.height) / 2, width: itemSize.width, height: itemSize.height)
            topRow.addSubview(item)
            right -= 10
        }
        // The title gives way to the items at the right, as in the main window.
        title.lineBreakMode = .byTruncatingTail
        title.sizeToFit()
        title.frame = NSRect(x: 20, y: (52 - title.frame.height) / 2, width: min(title.frame.width, right - 30),
                             height: title.frame.height)
        topRow.addSubview(title)
        controller.view.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height - 52)
        content.addSubview(controller.view)
        content.addSubview(topRow)
        window.contentView = content
        window.backgroundColor = controller.context.palette.background
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.orderFrontRegardless()
    }

    /// Lets AppKit lay out and draw for a moment.
    func settle(seconds: Double = 0.4) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    /// Draws the window's content into a bitmap at the backing scale. This
    /// works while the screen is locked, where a screen capture does not.
    /// Layer effects, such as an animation that runs, do not show.
    func capture(to path: URL) throws {
        settle(seconds: 0.2)
        let view = try #require(window.contentView)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: path)
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

/// The background of the window, drawn so that a cached picture has it.
final class PictureBackgroundView: NSView {
    var color = NSColor.windowBackgroundColor

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        dirtyRect.fill()
    }
}
