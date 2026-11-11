import Foundation
import SessionProcessHarness
import SessionProtocol
import Testing

/// A connection attached to a session, as a window is, once its snapshot came.
func attachedConnection(to process: RunningSessionProcess, session identifier: String) throws -> MessageConnection {
    let connection = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
    _ = try connection.greetSessionProcess(within: .seconds(5))
    try connection.send(ClientMessage.attach(identifier: try #require(UUID(uuidString: identifier)), size: SessionSize(columns: 80, rows: 24)))
    for _ in 0..<2 { _ = try connection.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .seconds(10))) }
    return connection
}

extension SessionProcessIntegration {
    /// The alert of a session (decision of 2026-11-10).
    @Suite struct SessionAlertTests {
        @Test(arguments: [
            (#"printf '\a'"#, SessionAlert.Source.bell, ""),
            (#"printf '\033]9;Build done\007'"#, .terminalNotification, "Build done"),
            (#"printf '\033]777;notify;Claude Code;Waiting for input\033\\'"#, .terminalNotification, "Waiting for input"),
            (#"printf '\033]99;i=1:d=0;Tests\033\\\033]99;i=1:p=body;All passed\033\\'"#, .terminalNotification, "All passed"),
        ])
        func eachSignalOfTheProgramRaisesTheAlert(command: String, source: SessionAlert.Source, text: String) async throws {
            try await RunningSessionProcess.run { process in
                let watcher = try SessionChangeWatcher(process)
                let identifier = try process.createSession(program: ["/bin/sh", "-c", "sleep 0.5; \(command); exec sleep 60"])
                let alerted = watcher.summary(of: identifier) { $0.alert != nil }
                #expect(alerted?.alert?.source == source && alerted?.alert?.text == text)
            }
        }

        /// The progress report of ConEmu shares OSC 9 and is no notification.
        @Test func aProgressReportRaisesNoAlert() async throws {
            try await RunningSessionProcess.run { process in
                let watcher = try SessionChangeWatcher(process)
                let script = #"printf '\033]9;4;1;50\007\033]9;4;0\007\033]2;after the report\007'; exec sleep 60"#
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                let titled = watcher.summary(of: identifier) { $0.title == "after the report" }
                #expect(titled != nil && titled?.alert == nil)
            }
        }

        /// The keys of an attached client end the alert. Text that another
        /// program sends does not.
        @Test func theKeysOfAnAttachedClientEndTheAlert() async throws {
            try await RunningSessionProcess.run { process in
                let watcher = try SessionChangeWatcher(process)
                let identifier = try process.createSession(program: ["/bin/sh", "-c", #"stty raw -echo; printf '\033]9;Approve?\007'; exec sleep 60"#])
                #expect(watcher.summary(of: identifier) { $0.alert?.text == "Approve?" } != nil)
                #expect(try process.runCommand(["send", identifier, "from a program"]).status == 0)
                #expect(watcher.summary(of: identifier) { $0.lastInputAt != nil } != nil)
                #expect(try listedSummaries(of: process).first?.alert?.text == "Approve?")
                let window = try attachedConnection(to: process, session: identifier)
                defer { window.shutdown() }
                try window.send(ClientMessage.input(Data("y".utf8)))
                #expect(watcher.summary(of: identifier) { $0.alert == nil } != nil)
            }
        }

        /// A shell rings the bell when a completion fails, while the user types.
        @Test func aBellRightAfterATypedKeyRaisesNoAlert() async throws {
            try await RunningSessionProcess.run { process in
                let watcher = try SessionChangeWatcher(process)
                let script = #"stty raw -echo; printf ready; dd bs=1 count=1 2>/dev/null; printf '\a\033]2;after the bell\007'; exec sleep 60"#
                let identifier = try process.createSession(program: ["/bin/sh", "-c", script])
                #expect(await process.waitForScreen(of: identifier, containing: "ready"))
                let window = try attachedConnection(to: process, session: identifier)
                defer { window.shutdown() }
                try window.send(ClientMessage.input(Data("\t".utf8)))
                let titled = watcher.summary(of: identifier) { $0.title == "after the bell" }
                #expect(titled != nil && titled?.alert == nil)
            }
        }
    }
}
