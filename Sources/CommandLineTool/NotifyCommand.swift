import Darwin
import SessionConnection
import SessionProtocol

/// `openrun notify`: raises the alert of a session, so that the user sees
/// that the session needs them. The hooks of an agent call it. When no
/// session process knows the session, the command tells the terminal with
/// OSC 777, which OpenRun and other terminals show (decision of 2026-11-10).
struct NotifyCommand {
    /// The session from `--session`. Nil means the session of the caller.
    var identifier: String?
    var text: String

    func run(socketFlag: String?, environment: [String: String]) throws {
        if try raiseAlert(socketFlag: socketFlag, environment: environment) { return }
        try tellTerminal()
    }

    /// Whether the session process took the alert. A refusal by the rule
    /// for callers is an error: the terminal belongs to another session. So
    /// is a session after `--session` that the session process does not
    /// know, because the user named it. A session from `OPENRUN_SESSION` can
    /// belong to another session process, and its alert goes to the terminal.
    private func raiseAlert(socketFlag: String?, environment: [String: String]) throws -> Bool {
        guard let typed = identifier ?? environment[SessionEnvironment.sessionName],
              let location = try? SocketLocation.resolve(flag: socketFlag, environment: environment) else { return false }
        do {
            // A hook must not wait without end for a session process that hangs.
            let client = try SessionClient(location: location, helloTimeLimit: .seconds(5))
            let session = try client.session(matching: typed)
            try client.raiseAlert(session: session.identifier, text: text)
            return true
        } catch let error as SessionConnectionError where Self.meansNoSessionProcess(error) {
            return false
        } catch let error as SessionConnectionError where identifier == nil && Self.meansUnknownSession(error) {
            return false
        }
    }

    private static func meansNoSessionProcess(_ error: SessionConnectionError) -> Bool {
        switch error {
        case .noSessionProcess, .wakeFailed, .protocolFailure, .connectionClosed: true
        default: false
        }
    }

    private static func meansUnknownSession(_ error: SessionConnectionError) -> Bool {
        switch error {
        case .noMatchingSession: true
        case .requestFailed(let failure): failure.reason == .unknownSession
        default: false
        }
    }

    /// The terminal must not wait for a reader, so the write does not block.
    private func tellTerminal() throws {
        let descriptor = open("/dev/tty", O_WRONLY | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw CommandLineToolError.failure("No session process took the alert, and the command has no terminal to tell.")
        }
        defer { close(descriptor) }
        let sequence = Array("\u{1B}]777;notify;OpenRun;\(SessionSummary.boundedText(text))\u{1B}\\".utf8)
        let written = sequence.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == sequence.count else {
            throw CommandLineToolError.failure("No session process took the alert, and the terminal did not take it.")
        }
    }
}
