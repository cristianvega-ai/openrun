import DataStorage
import Foundation
import OSLog
import Synchronization

/// Reads and writes `layout.json` for the app.
///
/// A write waits for the disk, so it runs on a queue of its own, and the
/// main thread never waits for it. Only the newest layout that waits is
/// written, so a fast series of changes costs one write.
public final class WindowLayoutStore: Sendable {
    private let dataFolder: DataFolder
    private let queue = DispatchQueue(label: "ai.cristianvega.openrun.layout", qos: .utility)
    private let waiting = Mutex<WindowLayout?>(nil)
    private let logger = Logger(subsystem: "ai.cristianvega.openrun", category: "WindowLayout")

    public init(dataFolder: DataFolder) {
        self.dataFolder = dataFolder
    }

    /// The kept layout, or a new one when there is no file. A file that
    /// this build cannot read is set aside, as each file of the data
    /// folder is, and the window starts with a new layout.
    public func load() -> WindowLayout {
        do {
            return try dataFolder.read(WindowLayout.self).document ?? WindowLayout()
        } catch {
            logger.error("The window layout could not be read: \(String(describing: error), privacy: .private)")
            return WindowLayout()
        }
    }

    /// Writes the layout soon. A later call before the write replaces it.
    public func save(_ layout: WindowLayout) {
        let isFirst = waiting.withLock { waiting in
            defer { waiting = layout }
            return waiting == nil
        }
        if isFirst { queue.async { [self] in writeWaiting() } }
    }

    /// Writes a layout that waits before it returns, such as when the
    /// app quits.
    public func finishWrites() {
        queue.sync { writeWaiting() }
    }

    private func writeWaiting() {
        let layout = waiting.withLock { waiting in
            defer { waiting = nil }
            return waiting
        }
        guard let layout else { return }
        do {
            try dataFolder.create()
            try dataFolder.write(layout)
        } catch {
            logger.error("The window layout could not be saved: \(String(describing: error), privacy: .private)")
        }
    }
}
