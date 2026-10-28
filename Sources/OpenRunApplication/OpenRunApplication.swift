import AppKit
import SessionConnection
import SessionLaunch
import SessionProtocol
import SessionWindow

/// The application delegate starts the session process and its windows.
@MainActor
public final class OpenRunApplication: NSObject, NSApplicationDelegate {
    private let socket: SocketLocation
    let windows: WindowList
    var makeNewSession: () -> SessionStart = { .newSessionInHomeFolder() }
    private var setupIsReady = false

    init(socket: SocketLocation) {
        self.socket = socket
        windows = WindowList(socket: socket)
        super.init()
    }

    /// Starts the application. It returns only when the application ends.
    public static func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        do {
            let arguments = try ApplicationArguments(arguments: Array(CommandLine.arguments.dropFirst()), environment: ProcessInfo.processInfo.environment)
            let delegate = OpenRunApplication(socket: arguments.socket)
            application.delegate = delegate
            withExtendedLifetime(delegate) { application.run() }
        } catch {
            application.activate()
            let alert = NSAlert()
            alert.messageText = "OpenRun could not start"
            alert.informativeText = String(describing: error)
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
        // Only the default socket belongs to the launch agent.
        guard socket.isDefault else { return finishSetup(.ready) }
        Thread.detachNewThread { [weak self] in
            let outcome = LaunchAgentSetup(source: LaunchAgentRegistration(), connect: Self.connect, ask: Self.ask).run()
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.finishSetup(outcome) }
            }
        }
    }

    private func finishSetup(_ outcome: LaunchAgentSetup.Outcome) {
        guard outcome == .ready else { return }
        setupIsReady = true
        windows.open(makeNewSession())
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if setupIsReady, windows.controllers.isEmpty { windows.open(makeNewSession()) }
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    public func applicationWillTerminate(_ notification: Notification) { windows.closeAll() }

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
