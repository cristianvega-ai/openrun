import AppKit
import Foundation
@testable import MainWindow

/// Defaults of their own for one test, so no test reads or changes the app's.
func temporaryDefaults() -> UserDefaults {
    let name = "MainWindowTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// A main window that keeps no frame, with its layout in temporary defaults.
@MainActor
func makeMainWindow(defaults: UserDefaults = temporaryDefaults()) -> MainWindowController {
    _ = NSApplication.shared
    let controller = MainWindowController(defaults: defaults, frameName: nil)
    controller.window.setContentSize(NSSize(width: 1_100, height: 700))
    controller.window.layoutIfNeeded()
    return controller
}
