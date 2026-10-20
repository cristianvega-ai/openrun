import Darwin
import Foundation
@testable import SessionProcess
import SessionProcessHarness
@testable import SessionProtocol
import Testing

private typealias Harness = SocketSecurityHarness

/// The frame that a session process of this version sends for hello. A
/// stand-in that sends it passes for a session process.
private func helloFrame() throws -> Data {
    try ServerMessage.hello(protocolVersion: MessageFrame.protocolVersion).frame().encoded()
}

/// Whether a session process answers hello on the socket within two seconds.
private func answersHello(_ socketPath: String) -> Bool {
    guard let connection = try? MessageConnection.connect(to: SocketLocation(path: socketPath)) else { return false }
    let watchdog = DispatchWorkItem { connection.shutdown() }
    DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: watchdog)
    defer {
        watchdog.cancel()
        connection.shutdown()
    }
    return (try? connection.greetSessionProcess()) != nil
}

/// Connects, and tries again while the system refuses because its queue of
/// waiting connections is full. The queue holds as many connections as the
/// listener asks for. On a busy machine the listener accepts late, so a burst
/// that is longer than the queue meets a full queue. The refusal comes from
/// the burst and not from the limit under test, so the test waits for the
/// listener to accept and connects again.
private func connectWhenTheQueueHasRoom(to location: SocketLocation) async throws -> MessageConnection {
    let deadline = ContinuousClock.now + .seconds(30)
    while true {
        do {
            return try MessageConnection.connect(to: location)
        } catch SessionProtocolError.systemCallFailed("connect", let code) where code == ECONNREFUSED && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// The path with every symbolic link resolved, to compare two spellings.
private func resolved(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}

extension SessionProcessIntegration {
    @Suite struct SocketSecurityTests {
        // MARK: - The folder of the socket

        @Test(arguments: [0o770, 0o707, 0o1777] as [mode_t])
        func aSessionProcessRefusesAFolderThatOtherUsersCanWrite(mode: mode_t) async throws {
            let folder = try Harness.makeFolder(mode: mode)
            defer { try? FileManager.default.removeItem(at: folder) }
            let logs = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: logs) }
            let socketPath = folder.appendingPathComponent("socket").path

            let process = try Harness.StartedSessionProcess(arguments: ["--socket", socketPath], folder: logs, logFile: logs.appendingPathComponent("log"))
            defer { process.stop() }
            #expect(await process.waitForExit(timeout: 5) == 1)
            #expect(process.log.contains(folder.path) && process.log.contains("write"), "log: \(process.log)")
            #expect(!FileManager.default.fileExists(atPath: socketPath))
            // A folder that the user chose keeps its mode. Only the default
            // folder belongs to OpenRun.
            #expect(Harness.mode(of: folder.path) == mode)
        }

        @Test(.enabled(if: geteuid() != 0))
        func bothSidesRefuseAFolderOfAnotherUser() async throws {
            // The system owns /usr. Nobody but root can put a socket there.
            let socketPath = "/usr/openrun-test-\(UInt32.random(in: 0...UInt32.max)).socket"
            let logs = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: logs) }

            let process = try Harness.StartedSessionProcess(arguments: ["--socket", socketPath], folder: logs, logFile: logs.appendingPathComponent("log"))
            defer { process.stop() }
            #expect(await process.waitForExit(timeout: 5) == 1)
            #expect(process.log.contains("/usr") && process.log.contains("another user"), "log: \(process.log)")

            let tool = try RunningSessionProcess.runOpenrun(["list", "--socket", socketPath], in: logs)
            #expect(tool.status == 1)
            #expect(tool.standardError.contains("/usr") && tool.standardError.contains("another user"), "stderr: \(tool.standardError)")
        }

        /// A program of the same user listens in a folder that others can
        /// write, and answers hello as a session process would. The client
        /// refuses the folder before it connects, so the squatter learns
        /// nothing: not the environment, the folder or the command of a new
        /// session. The session process refuses to start there too.
        @Test(arguments: [0o770, 0o777] as [mode_t])
        func aSquatterInAFolderThatOtherUsersCanWriteGetsNothing(mode: mode_t) async throws {
            let folder = try Harness.makeFolder(mode: mode)
            defer { try? FileManager.default.removeItem(at: folder) }
            let logs = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: logs) }
            let socketPath = folder.appendingPathComponent("socket").path
            let squatter = try Harness.StandInListener(path: socketPath, behavior: .answers(helloFrame()))
            defer { squatter.close() }
            let squatterFile = Harness.fileIdentity(at: socketPath)

            let new = try RunningSessionProcess.runOpenrun(
                ["new", "--socket", socketPath, "--", "/bin/sh"],
                environment: ["OPENRUN_TEST_SECRET": "a token the squatter must not see"],
                in: logs
            )
            #expect(new.status == 1)
            #expect(new.standardError.contains(folder.path) && new.standardError.contains("write"), "stderr: \(new.standardError)")
            let list = try RunningSessionProcess.runOpenrun(["list", "--socket", socketPath], in: logs)
            #expect(list.status == 1)

            let process = try Harness.StartedSessionProcess(arguments: ["--socket", socketPath], folder: logs, logFile: logs.appendingPathComponent("log"))
            defer { process.stop() }
            #expect(await process.waitForExit(timeout: 5) == 1)
            #expect(process.log.contains(folder.path) && process.log.contains("write"), "log: \(process.log)")

            #expect(squatter.acceptedCount == 0, "the squatter accepted \(squatter.acceptedCount) connections")
            #expect(squatter.receivedByteCount == 0, "the squatter received \(squatter.receivedByteCount) bytes")
            #expect(Harness.fileIdentity(at: socketPath) == squatterFile)
        }

        /// A folder of mode 0700 whose access control list
        /// lets everyone add and delete files passed the check, so another
        /// user could replace the socket.
        @Test func bothSidesRefuseAFolderWhoseAccessControlListLetsOthersChangeIt() async throws {
            let folder = try Harness.makeFolder(mode: 0o700)
            defer {
                Harness.removeAccessControlLists(under: folder.path)
                try? FileManager.default.removeItem(at: folder)
            }
            try Harness.addAccessControlEntry("everyone allow add_file,delete_child", to: folder.path)
            let logs = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: logs) }
            let socketPath = folder.appendingPathComponent("socket").path

            let process = try Harness.StartedSessionProcess(arguments: ["--socket", socketPath], folder: logs, logFile: logs.appendingPathComponent("log"))
            defer { process.stop() }
            #expect(await process.waitForExit(timeout: 5) == 1)
            #expect(process.log.contains(folder.path) && process.log.contains("access control list"), "log: \(process.log)")
            #expect(!FileManager.default.fileExists(atPath: socketPath))

            let tool = try RunningSessionProcess.runOpenrun(["list", "--socket", socketPath], in: logs)
            #expect(tool.status == 1)
            #expect(tool.standardError.contains(folder.path) && tool.standardError.contains("access control list"), "stderr: \(tool.standardError)")
        }

        /// A file in the place of the folder passed the
        /// check, and both sides failed later with a bare "Not a directory".
        @Test func bothSidesRefuseAFileInThePlaceOfTheSocketFolderByName() async throws {
            let logs = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: logs) }
            let file = logs.appendingPathComponent("plain").path
            #expect(FileManager.default.createFile(atPath: file, contents: Data("text".utf8)))
            let socketPath = file + "/socket"

            let process = try Harness.StartedSessionProcess(arguments: ["--socket", socketPath], folder: logs, logFile: logs.appendingPathComponent("log"))
            defer { process.stop() }
            #expect(await process.waitForExit(timeout: 5) == 1)
            #expect(process.log.contains(file) && process.log.contains("is not a folder"), "log: \(process.log)")

            let tool = try RunningSessionProcess.runOpenrun(["list", "--socket", socketPath], in: logs)
            #expect(tool.status == 1)
            #expect(tool.standardError.contains(file) && tool.standardError.contains("is not a folder"), "stderr: \(tool.standardError)")
            #expect((try? String(contentsOfFile: file, encoding: .utf8)) == "text")
        }

        // MARK: - What counts as a live session process

        /// Only a program that answers hello is a session process. A listener
        /// that never answers is replaced, and the log says so.
        @Test func aListenerThatNeverAnswersHelloIsNotTakenForASessionProcess() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let socketPath = folder.appendingPathComponent("socket").path
            let listener = try Harness.StandInListener(path: socketPath, behavior: .neverAnswers)
            defer { listener.close() }

            let process = try Harness.StartedSessionProcess(arguments: ["--socket", socketPath], folder: folder, logFile: folder.appendingPathComponent("log"))
            defer { process.stop() }
            // Until the session process has replaced the socket, a client would
            // wait for the stand-in's answer. So the test waits for the log.
            try #require(await process.waitForLog(containing: "Listening on"), "log: \(process.log)")
            #expect(process.isRunning)
            #expect(process.log.contains("did not answer"), "log: \(process.log)")
            #expect(listener.acceptedCount >= 1)

            let list = try RunningSessionProcess.runOpenrun(["list", "--socket", socketPath], in: folder)
            #expect(list.status == 0, "stderr: \(list.standardError)")
        }

        /// The check of a listener that never answers takes
        /// two seconds, and the socket file was then removed without a look
        /// at what the path held by then. A file that another program put
        /// there meanwhile was lost.
        @Test(arguments: [false, true])
        func aFileThatReplacesTheSocketDuringTheCheckIsLeftAlone(replacementIsASocket: Bool) async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let socketPath = folder.appendingPathComponent("socket").path
            let silent = try Harness.StandInListener(path: socketPath, behavior: .neverAnswers)
            defer { silent.close() }

            let process = try Harness.StartedSessionProcess(arguments: ["--socket", socketPath], folder: folder, logFile: folder.appendingPathComponent("log"))
            defer { process.stop() }
            // The session process has connected and now waits for hello.
            try #require(await eventually(timeout: .seconds(5)) { silent.acceptedCount >= 1 }, "log: \(process.log)")
            #expect(unlink(socketPath) == 0)
            var replacement: Harness.StandInListener?
            if replacementIsASocket {
                replacement = try Harness.StandInListener(path: socketPath, behavior: .boundOnly)
            } else {
                #expect(FileManager.default.createFile(atPath: socketPath, contents: Data("marker".utf8)))
            }
            defer { replacement?.close() }
            let replacementFile = try #require(Harness.fileIdentity(at: socketPath))

            #expect(await process.waitForExit(timeout: 10) == 1, "log: \(process.log)")
            #expect(process.log.contains(socketPath) && process.log.contains("left alone"), "log: \(process.log)")
            #expect(Harness.fileIdentity(at: socketPath) == replacementFile)
            if !replacementIsASocket {
                #expect((try? String(contentsOfFile: socketPath, encoding: .utf8)) == "marker")
            }
        }

        // MARK: - Relative socket paths

        /// A bare file name works, and every program gets the absolute path,
        /// so the path still leads to the session process from other folders.
        @Test func aRelativeSocketPathIsMadeAbsoluteBeforeAnyoneUsesIt() async throws {
            let root = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let serverFolder = root.appendingPathComponent("srv")
            let callerFolder = root.appendingPathComponent("caller")
            let sessionFolder = root.appendingPathComponent("session")
            for folder in [serverFolder, callerFolder, sessionFolder] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            let socketPath = serverFolder.appendingPathComponent("socket").path

            let process = try Harness.StartedSessionProcess(arguments: ["--socket", "socket"], folder: serverFolder, logFile: root.appendingPathComponent("log"))
            defer { process.stop() }
            try #require(await process.waitForLog(containing: "Listening on"), "log: \(process.log)")
            #expect(FileManager.default.fileExists(atPath: socketPath))

            // A client in another folder gives a relative path of its own.
            let seenFile = sessionFolder.appendingPathComponent("seen")
            let created = try RunningSessionProcess.runOpenrun(
                ["new", "--socket", "../srv/socket", "--folder", sessionFolder.path, "--",
                 "/bin/sh", "-c", "printf '%s' \"$OPENRUN_SOCKET\" > seen; exec sleep 300"],
                folder: callerFolder,
                in: root
            )
            #expect(created.status == 0, "stderr: \(created.standardError)")
            #expect(await eventually { ((try? String(contentsOf: seenFile, encoding: .utf8)) ?? "").hasSuffix("socket") })
            let seen = (try? String(contentsOf: seenFile, encoding: .utf8)) ?? ""
            #expect(seen.hasPrefix("/"), "OPENRUN_SOCKET=\(seen)")
            #expect(resolved(seen) == resolved(socketPath), "OPENRUN_SOCKET=\(seen)")

            // In the program's folder, the variable still leads to the
            // session process. A relative OPENRUN_SOCKET works as well.
            let fromSession = try RunningSessionProcess.runOpenrun(["list"], folder: sessionFolder, environment: ["OPENRUN_SOCKET": seen], in: root)
            #expect(fromSession.status == 0 && fromSession.outputLines.count == 1, "stderr: \(fromSession.standardError)")
            let fromCaller = try RunningSessionProcess.runOpenrun(["list"], folder: callerFolder, environment: ["OPENRUN_SOCKET": "../srv/socket"], in: root)
            #expect(fromCaller.status == 0 && fromCaller.outputLines.count == 1, "stderr: \(fromCaller.standardError)")
        }

        /// An absolute path kept its "." and "..", and
        /// reached every program in `OPENRUN_SOCKET` as it was spelled.
        @Test func anAbsoluteSocketPathReachesProgramsWithoutItsDots() async throws {
            let root = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let serverFolder = root.appendingPathComponent("srv")
            try FileManager.default.createDirectory(at: serverFolder, withIntermediateDirectories: true)
            let plainPath = serverFolder.appendingPathComponent("socket").path
            let spelledPath = root.path + "/srv/../srv/./socket"

            let process = try Harness.StartedSessionProcess(arguments: ["--socket", spelledPath], folder: root, logFile: root.appendingPathComponent("log"))
            defer { process.stop() }
            try #require(await process.waitForLog(containing: "Listening on"), "log: \(process.log)")
            #expect(process.log.contains("Listening on \(plainPath)\n"), "log: \(process.log)")

            let seenFile = serverFolder.appendingPathComponent("seen")
            let created = try RunningSessionProcess.runOpenrun(
                ["new", "--socket", spelledPath, "--folder", serverFolder.path, "--",
                 "/bin/sh", "-c", "printf '%s' \"$OPENRUN_SOCKET\" > seen; exec sleep 300"],
                in: root
            )
            #expect(created.status == 0, "stderr: \(created.standardError)")
            #expect(await eventually { ((try? String(contentsOf: seenFile, encoding: .utf8)) ?? "").hasSuffix("socket") })
            let seen = (try? String(contentsOf: seenFile, encoding: .utf8)) ?? ""
            #expect(seen == plainPath, "OPENRUN_SOCKET=\(seen)")
        }

        // MARK: - One session process per socket

        @Test func aRunningSessionProcessHoldsTheLockOfItsSocket() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let descriptor = Harness.takeSocketLock(forSocket: process.socketPath)
            if let descriptor { close(descriptor) }
            #expect(descriptor == nil)
        }

        /// A lock file made beforehand kept its mode, so
        /// another user who could open it could hold the lock.
        @Test func aLockFileThatOthersCouldOpenIsMadePrivate() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let socketPath = folder.appendingPathComponent("socket").path
            let lockPath = Harness.lockPath(forSocket: socketPath)
            #expect(FileManager.default.createFile(atPath: lockPath, contents: nil))
            #expect(chmod(lockPath, 0o666) == 0)

            let process = try Harness.StartedSessionProcess(arguments: ["--socket", socketPath], folder: folder, logFile: folder.appendingPathComponent("log"))
            defer { process.stop() }
            try #require(await process.waitForLog(containing: "Listening on"), "log: \(process.log)")
            #expect(Harness.mode(of: lockPath) == 0o600)
        }

        /// What sat at the lock path was used as it was. A
        /// named pipe gave a bare flock error. Each kind is now refused by
        /// name and left as it is.
        @Test(arguments: ["named pipe", "symbolic link", "folder"])
        func aLockPathThatIsNotARegularFileIsRefusedAndLeftAlone(kind: String) async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let socketPath = folder.appendingPathComponent("socket").path
            let lockPath = Harness.lockPath(forSocket: socketPath)
            let target = folder.appendingPathComponent("target").path
            #expect(FileManager.default.createFile(atPath: target, contents: Data("target".utf8)))
            #expect(chmod(target, 0o644) == 0)
            switch kind {
            case "named pipe": #expect(mkfifo(lockPath, 0o600) == 0)
            case "symbolic link": #expect(symlink(target, lockPath) == 0)
            default: #expect(mkdir(lockPath, 0o700) == 0)
            }
            let before = try #require(Harness.fileIdentity(at: lockPath))

            let process = try Harness.StartedSessionProcess(arguments: ["--socket", socketPath], folder: folder, logFile: folder.appendingPathComponent("log"))
            defer { process.stop() }
            #expect(await process.waitForExit(timeout: 5) == 1)
            #expect(process.log.contains(lockPath) && process.log.contains("not a regular file"), "log: \(process.log)")
            #expect(Harness.fileIdentity(at: lockPath) == before)
            #expect(Harness.mode(of: target) == 0o644)
            #expect(!FileManager.default.fileExists(atPath: socketPath))
        }

        /// A lock file of another user would let that user
        /// hold the lock. This Mac has one user, so the test makes the lock
        /// expect another owner than the file has.
        @Test func aLockFileOfAnotherUserIsRefusedAndLeftAlone() throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let socketPath = folder.appendingPathComponent("socket").path
            let lockPath = Harness.lockPath(forSocket: socketPath)
            #expect(FileManager.default.createFile(atPath: lockPath, contents: nil))
            #expect(chmod(lockPath, 0o644) == 0)

            let error = #expect(throws: SessionProcessError.self) {
                _ = try SocketListener.SocketLock(socketPath: socketPath, owner: geteuid() &+ 1)
            }
            let message = error?.description ?? ""
            #expect(message.contains(lockPath) && message.contains("another user"), "\(message)")
            #expect(Harness.mode(of: lockPath) == 0o644)
            // The owner takes the same file, and only the owner may open it.
            let lock = try SocketListener.SocketLock(socketPath: socketPath)
            #expect(lock.path == lockPath)
            #expect(Harness.mode(of: lockPath) == 0o600)
        }

        /// While a session process starts, it has bound its socket and not
        /// yet listened, so a connection is refused as on a stale file. It
        /// already holds the lock, so a second process refuses to start, and
        /// the socket file of the first one stays.
        @Test func aSessionProcessThatIsStartingMakesASecondOneRefuse() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let socketPath = folder.appendingPathComponent("socket").path
            let lock = try #require(Harness.takeSocketLock(forSocket: socketPath))
            defer { close(lock) }
            let starting = try Harness.StandInListener(path: socketPath, behavior: .boundOnly)
            defer { starting.close() }
            let startingFile = Harness.fileIdentity(at: socketPath)

            let second = try Harness.StartedSessionProcess(arguments: ["--socket", socketPath], folder: folder, logFile: folder.appendingPathComponent("log"))
            defer { second.stop() }
            #expect(await second.waitForExit(timeout: 5) == 1)
            #expect(second.log.contains("already runs"), "log: \(second.log)")
            #expect(Harness.fileIdentity(at: socketPath) == startingFile)
        }

        /// At shutdown a session process removes the socket file only when the
        /// file at the path is still the one it created.
        @Test func shutdownLeavesASocketFileThatIsNoLongerItsOwn() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let moved = process.directory.appendingPathComponent("moved").path
            #expect(rename(process.socketPath, moved) == 0)
            let other = try Harness.StandInListener(path: process.socketPath, behavior: .boundOnly)
            defer { other.close() }
            let otherFile = Harness.fileIdentity(at: process.socketPath)

            process.send(signal: SIGTERM)
            #expect(await process.waitForExit() == 0)
            #expect(otherFile != nil && Harness.fileIdentity(at: process.socketPath) == otherFile)
        }

        /// Two session processes start on one fresh socket at the same moment,
        /// many times. Each time exactly one survives, and its socket stays
        /// and answers until it stops.
        @Test func ofTwoSessionProcessesStartedTogetherExactlyOneSurvives() async throws {
            for round in 1...30 {
                let folder = try RunningSessionProcess.makeDirectory()
                defer { try? FileManager.default.removeItem(at: folder) }
                let socketPath = folder.appendingPathComponent("socket").path
                let pair = try Harness.startTogether(count: 2, socketPath: socketPath, folder: folder)
                defer { for process in pair { process.stop() } }

                let settled = await eventually(timeout: .seconds(10)) {
                    pair.filter(\.isRunning).count == 1 && answersHello(socketPath)
                }
                // A second process that also survived could need a moment to
                // show it, so look again after a short wait.
                try? await Task.sleep(for: .milliseconds(200))
                let survivors = pair.filter(\.isRunning)
                try #require(settled && survivors.count == 1,
                             "round \(round): \(survivors.count) running; logs: \(pair.map(\.log))")
                let survivor = survivors[0]
                let loser = pair.first { $0 !== survivor }!
                #expect(await loser.waitForExit(timeout: 5) == 1, "round \(round)")
                #expect(loser.log.contains("already runs"), "round \(round): \(loser.log)")
                #expect(answersHello(socketPath), "round \(round): the socket stopped answering")

                survivor.send(signal: SIGTERM)
                #expect(await survivor.waitForExit() == 0, "round \(round)")
                #expect(!FileManager.default.fileExists(atPath: socketPath), "round \(round)")
            }
        }

        // MARK: - The command line of openrun-session
        //
        // These belong to the start of a session process, as the lock does.

        @Test(arguments: [["--help", "extra"], ["--socket", "help-socket", "--help"], ["--help", "--help"]])
        func helpWithOtherArgumentsIsAUsageError(arguments: [String]) async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let process = try Harness.StartedSessionProcess(arguments: arguments, folder: folder, logFile: folder.appendingPathComponent("log"))
            defer { process.stop() }
            #expect(await process.waitForExit(timeout: 10) == 2)
            #expect(process.log.contains("Usage: openrun-session"), "log: \(process.log)")
        }

        @Test func helpAloneShowsTheUsage() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let process = try Harness.StartedSessionProcess(arguments: ["--help"], folder: folder, logFile: folder.appendingPathComponent("log"))
            defer { process.stop() }
            #expect(await process.waitForExit(timeout: 10) == 0)
            #expect(process.log.contains("Usage: openrun-session"))
        }

        // MARK: - The user at the other end
        //
        // This Mac has one user account, and a test cannot start a program as
        // another user. So these tests make each side expect another user
        // than the one it meets, through a parameter that only tests set.

        @Test func thePeerOfASocketIsTheUserOfThisProcess() throws {
            let (one, other) = try MessageConnection.makePair()
            #expect(throws: Never.self) { try one.requirePeer() }
            #expect(throws: Never.self) { try other.requirePeer(PeerIdentity(userIdentifier: geteuid())) }
        }

        /// A client refuses a session process of another user before it sends
        /// a byte.
        @Test func aClientRefusesASessionProcessOfAnotherUser() throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let location = try SocketLocation(path: folder.appendingPathComponent("socket").path)
            let server = try Harness.StandInListener(path: location.path, behavior: .answers(helloFrame()))
            defer { server.close() }
            let anotherUser = PeerIdentity(userIdentifier: geteuid() &+ 1)

            #expect(throws: SessionProtocolError.peerIsAnotherUser(expected: anotherUser.userIdentifier, found: geteuid())) {
                _ = try MessageConnection.connect(to: location, expectedPeer: anotherUser)
            }
            // The same stand-in, as the same user, is accepted and answers.
            let connection = try MessageConnection.connect(to: location)
            defer { connection.shutdown() }
            try connection.greetSessionProcess(within: .seconds(5))
            #expect(server.acceptedCount == 2)
            // Only the second connection said hello.
            let helloSize = try ClientMessage.hello(protocolVersion: MessageFrame.protocolVersion).frame().encoded().count
            #expect(server.receivedByteCount == helloSize)
        }

        /// The session process closes a connection of another user before it
        /// sends a byte, and never serves it.
        @Test func theSessionProcessRefusesAClientOfAnotherUser() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let anotherUser = PeerIdentity(userIdentifier: geteuid() &+ 1)

            for (allowed, served) in [(anotherUser, false), (PeerIdentity.currentUser, true)] {
                let location = try SocketLocation(path: folder.appendingPathComponent(served ? "served" : "refused").path)
                let listener = try SocketListener(location: location, allowedPeer: allowed)
                let connections = listener.connections
                let counting = Task {
                    var count = 0
                    for await connection in connections {
                        count += 1
                        connection.shutdown()
                    }
                    return count
                }
                let client = try MessageConnection.connect(to: location)
                // A refused client sees the connection end with no byte. A
                // served one waits for an answer that this test never gives.
                let answer = Result { try client.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .milliseconds(served ? 300 : 5000))) }
                client.shutdown()
                listener.close()
                let count = await counting.value
                if served {
                    #expect(count == 1)
                } else {
                    #expect(count == 0)
                    #expect(try answer.get() == nil)
                }
            }
        }

        // MARK: - Connections that wait for the server

        /// The listener kept every connection it accepted
        /// until the server took it, with no limit, outside the client limit
        /// and before the hello deadline. Now a fixed number wait, and the
        /// listener closes the rest at once.
        @Test func connectionsPastTheLimitThatWaitForTheServerAreClosedAtOnce() async throws {
            let folder = try RunningSessionProcess.makeDirectory()
            defer { try? FileManager.default.removeItem(at: folder) }
            let location = try SocketLocation(path: folder.appendingPathComponent("socket").path)
            let listener = try SocketListener(location: location)
            let limit = SocketListener.waitingConnectionLimit
            let clientCount = limit + 24
            // Nothing takes the connections, as when the server is busy.
            var clients: [MessageConnection] = []
            defer { clients.forEach { $0.shutdown() } }
            for _ in 0..<clientCount {
                clients.append(try await connectWhenTheQueueHasRoom(to: location))
            }

            let closed = await eventually(timeout: .seconds(5)) {
                clients.filter(\.peerHasClosed).count >= clientCount - limit
            }
            let closedCount = clients.filter(\.peerHasClosed).count
            #expect(closed && closedCount == clientCount - limit, "\(closedCount) of \(clientCount) connections were closed")
            let waitingClosed = clients.prefix(limit).filter(\.peerHasClosed).count
            #expect(waitingClosed == 0, "\(waitingClosed) of the connections that wait were closed")

            listener.close()
            var waited = 0
            for await connection in listener.connections {
                waited += 1
                connection.shutdown()
            }
            #expect(waited == limit)
        }
    }
}
