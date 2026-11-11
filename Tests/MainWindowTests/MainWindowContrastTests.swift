import AppKit
import Testing
@testable import MainWindow
@testable import PaneAppearance
@testable import SessionsList

/// A view that counts the requests to draw it again.
@MainActor
final class DrawingProbeView: NSView {
    var drawRequests = 0
    override var needsDisplay: Bool {
        didSet { if needsDisplay { drawRequests += 1 } }
    }
}

/// A change of Increase Contrast draws the window again, and the layer
/// marks take the new colors.
@MainActor @Suite(.serialized) struct MainWindowContrastTests {
    @Test func aChangeOfContrastDrawsTheWindowAgain() throws {
        let controller = makeMainWindow()
        defer {
            controller.window.close()
            PaneColor.contrastSetting.withLock { $0 = nil }
        }
        let now = Date()
        let row = SessionRowDisplay(identifier: UUID(), title: "swift test", folder: "~/p", kind: .terminal, isInProgress: true, lastActivity: now, startTime: now)
        controller.sessionsList.show(SessionsListContent(title: "p", rows: [row], agents: []))
        controller.window.layoutIfNeeded()
        let cell = try #require(controller.sessionsList.table.view(atColumn: 0, row: 0, makeIfNecessary: false) as? SessionCellView)
        let probe = DrawingProbeView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        cell.addSubview(probe)
        let before = probe.drawRequests
        PaneColor.contrastSetting.withLock { $0 = true }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
        #expect(probe.drawRequests > before)
        // AppKit calls updateLayer when it draws a view that needs display.
        cell.progress.updateLayer()
        var strong: CGColor?
        cell.progress.effectiveAppearance.performAsCurrentDrawingAppearance { strong = PaneColor.quietText.cgColor }
        #expect(cell.progress.arc.strokeColor == strong)
    }
}
