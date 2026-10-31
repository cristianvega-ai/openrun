import AppKit
import SessionConnection
import SessionLaunch
import SessionProtocol
import SessionWindow

/// The application delegate starts the session process and its windows.
@MainActor
public final class OpenRunApplication: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let socket: SocketLocation
    let windows: WindowList
    var makeNewSession: () -> SessionStart = { .newSessionInHomeFolder() }
    var chooseSession: @MainActor (SocketLocation, NSWindow?) async -> UUID? = { await SessionList.choose(at: $0, in: $1) }
    private var setupIsReady = false
    private var setupIsRunning = false
    private let runLaunchAgentSetup: (@Sendable () -> LaunchAgentSetup.Outcome)?

    init(socket: SocketLocation, runLaunchAgentSetup: (@Sendable () -> LaunchAgentSetup.Outcome)? = nil) {
        self.socket = socket
        self.runLaunchAgentSetup = runLaunchAgentSetup
        windows = WindowList(socket: socket)
        super.init()
    }

    /// Starts the application. It returns only when the application ends.
    public static func run() {
        registerKeyboardDefaults()
        let application = NSApplication.shared
#if DEBUG
        // The screenshot test needs both appearances without a system change.
        switch ProcessInfo.processInfo.environment["OPENRUN_TEST_APPEARANCE"] {
        case "light": application.appearance = NSAppearance(named: .aqua)
        case "dark": application.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
#endif
        application.setActivationPolicy(.regular)
        do {
            let arguments = try ApplicationArguments(arguments: Array(CommandLine.arguments.dropFirst()), environment: ProcessInfo.processInfo.environment)
            let delegate = OpenRunApplication(socket: arguments.socket)
            application.delegate = delegate
            application.mainMenu = MainMenu.make(target: delegate)
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

    /// A registered default leaves an explicit user preference in force.
    static func registerKeyboardDefaults() {
        UserDefaults.standard.register(defaults: ["ApplePressAndHoldEnabled": false])
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
        // Only the default socket belongs to the launch agent.
        guard socket.isDefault || runLaunchAgentSetup != nil else { return finishSetup(.ready) }
        startSetup()
    }

    private func startSetup() {
        guard !setupIsReady, !setupIsRunning else { return }
        setupIsRunning = true
        let run: @Sendable () -> LaunchAgentSetup.Outcome = runLaunchAgentSetup ?? {
            LaunchAgentSetup(source: LaunchAgentRegistration(), connect: { try Self.connect(to: SocketLocation(path: SocketLocation.defaultPath)) }, ask: { ModalAlert.ask($0) }).run()
        }
        Thread.detachNewThread { [weak self] in
            let outcome = run()
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.finishSetup(outcome) }
            }
        }
    }

    private func finishSetup(_ outcome: LaunchAgentSetup.Outcome) {
        setupIsRunning = false
        guard outcome == .ready else { return }
        setupIsReady = true
        windows.open(makeNewSession())
    }

    @objc func retrySessionProcess(_ sender: Any?) { startSetup() }

    @objc func newSession(_ sender: Any?) {
        if setupIsReady { windows.open(makeNewSession()) }
    }

    @objc func attachToSession(_ sender: Any?) {
        guard setupIsReady else { return }
        Task { [weak self] in
            guard let self, let identifier = await chooseSession(socket, NSApp.keyWindow) else { return }
            windows.open(.runningSession(identifier))
        }
    }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(newSession(_:)), #selector(attachToSession(_:)): setupIsReady
        case #selector(retrySessionProcess(_:)): !setupIsReady && !setupIsRunning
        default: true
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if setupIsReady, windows.controllers.isEmpty { windows.open(makeNewSession()) }
        return true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    public func applicationWillTerminate(_ notification: Notification) { windows.closeAll() }

    /// Connects as each client does, so a wake goes out only when nothing
    /// listens on the socket. Every failure reaches the setup question.
    ///
    /// The hello has a time limit. A session process that takes the
    /// connection and never answers would keep the setup running for ever,
    /// and File > Retry Session Process would stay off.
    nonisolated static func connect(to location: SocketLocation, helloTimeLimit: Duration = SessionWake.answerTimeLimit) throws {
        do {
            _ = try SessionClient(location: location, helloTimeLimit: helloTimeLimit)
        } catch SessionConnectionError.wakeFailed(let failure) {
            throw failure
        } catch SessionConnectionError.protocolFailure(.timedOut) {
            throw LaunchAgentSetup.HelloTimedOut(limit: helloTimeLimit)
        }
    }
}
