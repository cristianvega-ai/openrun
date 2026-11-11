import AppKit
import SessionConnection
import SessionLaunch
import SessionProtocol

/// The application delegate starts the session process and the main window.
@MainActor
public final class OpenRunApplication: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let socket: SocketLocation
    /// The main window and its link to the session process.
    let workspace: Workspace
    private var setupIsReady = false
    private var setupIsRunning = false
    private let makeLaunchAgentSetup: (@Sendable () -> LaunchAgentSetup)?
    /// Receives the questions of the rule that asks the user first.
    let approvalQuestions: ApprovalQuestionConnection

    /// Only the default socket belongs to the launch agent. A nondefault socket
    /// with no injected setup would otherwise register the real agent of the
    /// running bundle, so the start and the File menu use this one rule.
    private var ownsLaunchAgent: Bool { socket.isDefault || makeLaunchAgentSetup != nil }

    /// - Parameter workspace: The host of the main window. Tests give one
    ///   that keeps no frame and shows no notification.
    init(socket: SocketLocation, makeLaunchAgentSetup: (@Sendable () -> LaunchAgentSetup)? = nil, workspace: Workspace? = nil) {
        self.socket = socket
        self.makeLaunchAgentSetup = makeLaunchAgentSetup
        self.workspace = workspace ?? Workspace(socket: socket)
        self.workspace.showsSessionAtStart = true
        approvalQuestions = ApprovalQuestionConnection(socket: socket)
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

    /// The window comes at once. Its lists fill when the session process
    /// is ready and the feed answers.
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
        workspace.showWindow()
        guard ownsLaunchAgent else { return finishSetup(.ready) }
        startSetup()
    }

    private func startSetup(registeringAgain: Bool = false) {
        guard !setupIsRunning, registeringAgain || !setupIsReady else { return }
        setupIsRunning = true
        let makeSetup: @Sendable () -> LaunchAgentSetup = makeLaunchAgentSetup ?? {
            LaunchAgentSetup(source: LaunchAgentRegistration(), connect: { try Self.connect(to: SocketLocation(path: SocketLocation.defaultPath)) }, ask: { ModalAlert.ask($0) })
        }
        Thread.detachNewThread { [weak self] in
            let setup = makeSetup()
            let outcome = registeringAgain ? setup.registerAgain() : setup.run()
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.finishSetup(outcome) }
            }
        }
    }

    private func finishSetup(_ outcome: LaunchAgentSetup.Outcome) {
        setupIsRunning = false
        guard outcome != .canceled else { return }
        // A new registration can fail after the app was ready. Then the app is
        // not ready, and File > Retry Session Process is on. The window and
        // its connection stay, and the connection tries again by itself.
        setupIsReady = outcome == .ready
        guard setupIsReady else { return }
        workspace.start()
        approvalQuestions.start()
    }

    @objc func retrySessionProcess(_ sender: Any?) { startSetup() }
    @objc func registerSessionProcessAgain(_ sender: Any?) {
        // A direct call can skip the menu check, so the action checks the rule too.
        guard ownsLaunchAgent else { return }
        startSetup(registeringAgain: true)
    }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(retrySessionProcess(_:)): !setupIsReady && !setupIsRunning
        case #selector(registerSessionProcessAgain(_:)): ownsLaunchAgent && !setupIsRunning
        default: true
        }
    }

    /// A click on the Dock icon shows the main window again after a close.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { workspace.showWindow() }
        return true
    }

    /// A close of the window leaves the app and every session running.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    public func applicationWillTerminate(_ notification: Notification) { workspace.stop() }

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
