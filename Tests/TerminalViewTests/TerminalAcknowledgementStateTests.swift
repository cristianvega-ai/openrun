import AppKit
import TerminalEmulation
import Testing
@testable import TerminalView

@MainActor @Suite struct TerminalAcknowledgementStateTests {
    @Test func unchangedSizeStillAcknowledgesTheRequest() throws {
        _ = NSApplication.shared
        let size = TerminalSize(columns: 80, rows: 24)
        let view = try TerminalView(initialGrid: size)
        let delegate = RecordingDelegate()
        view.delegate = delegate
        view.followSessionSize(size)
        #expect(delegate.appliedSizes == [size])
        #expect(delegate.sizes.isEmpty)
    }
}
