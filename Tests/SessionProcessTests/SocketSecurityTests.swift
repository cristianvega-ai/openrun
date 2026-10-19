import Darwin
import Foundation
@testable import SessionProcess
import SessionProcessHarness
@testable import SessionProtocol
import Testing

private typealias Harness = SocketSecurityHarness

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
        // MARK: - One session process per socket

        @Test func aRunningSessionProcessHoldsTheLockOfItsSocket() async throws {
            let process = try RunningSessionProcess()
            defer { process.stop() }
            let descriptor = Harness.takeSocketLock(forSocket: process.socketPath)
            if let descriptor { close(descriptor) }
            #expect(descriptor == nil)
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
                clients.append(try MessageConnection.connect(to: location))
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
