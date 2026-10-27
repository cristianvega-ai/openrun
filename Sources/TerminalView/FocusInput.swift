import AppKit
import TerminalEmulation
import os

/// Follows whether the window of the view is the key window. A program that
/// turned on mode 1004 wants to know, and the view draws a hollow cursor while the
/// window is not key.
@MainActor
final class FocusInput {
    private var observers: [any NSObjectProtocol] = []

    /// Called with `true` when the window becomes the key window, and `false` when it stops.
    var onChange: ((Bool) -> Void)?

    /// Follows another window, or none. The state of the new window is not a change.
    func follow(_ window: NSWindow?) {
        observers.forEach(NotificationCenter.default.removeObserver)
        // A notification with no object comes from every window, so a view with no window follows none.
        guard let window else { return observers = [] }
        observers = [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false)].map { name, isKey in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?(isKey) }
            }
        }
    }

    /// The bytes for a program that turned on mode 1004, or no bytes.
    static func report(gained: Bool, terminal: Terminal) -> [UInt8] {
        guard terminal.isModeEnabled(.focusReports) else { return [] }
        return (try? FocusReport.encode(gained: gained)) ?? []
    }
}
