import AppKit
import SessionConnection
import SessionLaunch
import SessionProtocol

/// The application delegate of OpenRun.app. In milestone 2 it only sets up
/// the launch agent at the start. A later milestone adds the window.
@MainActor
public final class OpenRunApplication: NSObject, NSApplicationDelegate {
    /// Starts the application. It returns only when the application ends.
    public static func run() {
        let application = NSApplication.shared
        let delegate = OpenRunApplication()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // A wake can wait 15 seconds for launchd, so the setup runs on a
        // thread of its own. Each question goes to the main thread.
        Thread.detachNewThread {
            _ = LaunchAgentSetup(source: LaunchAgentRegistration(), connect: Self.connect, ask: Self.ask).run()
        }
    }

    /// Connects as each client does, so a wake goes out only when nothing
    /// listens on the default socket. Every failure reaches the setup question.
    nonisolated private static func connect() throws {
        do {
            _ = try SessionClient(location: SocketLocation(path: SocketLocation.defaultPath))
        } catch SessionConnectionError.wakeFailed(let failure) {
            throw failure
        } catch {
            throw error
        }
    }

    nonisolated private static func ask(_ question: LaunchAgentQuestion) -> Bool {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                let words = question.words
                let alert = NSAlert()
                alert.messageText = words.title
                alert.informativeText = words.message
                for button in words.buttons { alert.addButton(withTitle: button) }
                NSApp.activate()
                return alert.runModal() == .alertFirstButtonReturn
            }
        }
    }
}
