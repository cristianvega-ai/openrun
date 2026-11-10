import Foundation
import SessionProcessHarness
import SessionProtocol
import TerminalEmulation
import Testing

extension SessionProcessIntegration {
    @Suite struct ResizeConfirmationTests {
        private static func next(on client: MessageConnection) throws -> ServerMessage {
            try #require(try client.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .seconds(15))))
        }

        private static func attach(to process: RunningSessionProcess, identifier: UUID, size: SessionSize) throws -> (MessageConnection, Data) {
            let client = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
            try client.greetSessionProcess()
            try client.send(ClientMessage.attach(identifier: identifier, size: size, receivesSizeChanges: true))
            guard case .attached = try next(on: client), case .snapshot(let snapshot) = try next(on: client) else {
                throw SessionProtocolError.unexpectedMessage(description: "The attach did not send a snapshot.")
            }
            return (client, snapshot)
        }

        @Test func theProcessConfirmsChangesAndNoOpRequestsAndRefusesInvalidSizes() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try #require(UUID(uuidString: process.createSession(program: ["/bin/sleep", "60"])))
                let client = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                let watchdog = DispatchWorkItem { client.shutdown() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
                defer { watchdog.cancel(); client.shutdown() }
                #expect(try client.greetSessionProcess().orderedResizeConfirmation)
                let initial = SessionSize(columns: 80, rows: 24)
                try client.send(ClientMessage.attach(identifier: identifier, size: initial))
                guard case .attached = try client.receive(ServerMessage.self),
                      case .snapshot = try client.receive(ServerMessage.self) else {
                    Issue.record("The client did not receive its snapshot.")
                    return
                }
                let changed = SessionSize(columns: 100, rows: 30)
                try client.send(ClientMessage.resize(changed, requestsConfirmation: true))
                #expect(try client.receive(ServerMessage.self) == .sizeChanged(changed))
                try client.send(ClientMessage.resize(changed, requestsConfirmation: true))
                #expect(try client.receive(ServerMessage.self) == .sizeChanged(changed))
                try client.send(ClientMessage.resize(SessionSize(columns: 0, rows: 30), requestsConfirmation: true))
                guard case .failure(let failure) = try client.receive(ServerMessage.self) else {
                    Issue.record("The client received no failure for an invalid size.")
                    return
                }
                #expect(failure.reason == .invalidRequest)
                #expect(try client.receive(ServerMessage.self, timeLimit: .wholeFrame(by: .now + .seconds(5))) == nil)
            }
        }

        @Test func foreignSizeAndEarlierOutputPrecedeTheRequestedSize() async throws {
            for requestsConfirmation in [false, true] {
                try await RunningSessionProcess.run { process in
                    let program = ["/bin/sh", "-c", "/bin/stty -echo; printf 'ready\\n'; read line; printf 'before\\n'; read line; printf 'after\\n'; /bin/sleep 60"]
                    let text = try process.createSession(program: program)
                    try #require(await process.waitForScreen(of: text, containing: "ready"))
                    let identifier = try #require(UUID(uuidString: text))
                    let initial = SessionSize(columns: 80, rows: 24)
                    let foreign = SessionSize(columns: 20, rows: 24)
                    let requested = SessionSize(columns: 40, rows: 24)
                    let (first, _) = try Self.attach(to: process, identifier: identifier, size: initial)
                    let (other, _) = try Self.attach(to: process, identifier: identifier, size: foreign)
                    defer { first.shutdown(); other.shutdown() }
                    try other.send(ClientMessage.input(Data("one\n".utf8)))
                    var observed = ""
                    while !observed.contains("before") {
                        if case .output(let bytes) = try Self.next(on: other) { observed += String(decoding: bytes, as: UTF8.self) }
                    }
                    let resize: ClientMessage = requestsConfirmation
                        ? .resize(requested, requestsConfirmation: true) : .resize(requested)
                    try first.send(resize)
                    try first.send(ClientMessage.input(Data("two\n".utf8)))
                    var sizes: [SessionSize] = []
                    var beforeConfirmation = ""
                    var afterConfirmation = ""
                    while !(beforeConfirmation + afterConfirmation).contains("after") {
                        switch try Self.next(on: first) {
                        case .sizeChanged(let size, _, _): sizes.append(size)
                        case .output(let bytes):
                            let text = String(decoding: bytes, as: UTF8.self)
                            if sizes.contains(requested) { afterConfirmation += text } else { beforeConfirmation += text }
                        default: break
                        }
                    }
                    #expect(sizes == (requestsConfirmation ? [foreign, requested] : [foreign]))
                    #expect(beforeConfirmation.contains("before"))
                    if requestsConfirmation { #expect(afterConfirmation.contains("after")) }
                }
            }
        }

        @Test func aFailedConfirmedResizeReportsFailureAndLeavesTheSize() async throws {
            try await RunningSessionProcess.run { process in
                let identifier = try #require(UUID(uuidString: process.createSession(program: ["/bin/sleep", "60"])))
                let initial = SessionSize(columns: 80, rows: 24)
                let (client, _) = try Self.attach(to: process, identifier: identifier, size: initial)
                defer { client.shutdown() }
                let refused = SessionSize(columns: Terminal.maximumGridDimension + 1, rows: 24)
                try client.send(ClientMessage.resize(refused, requestsConfirmation: true))
                guard case .failure(let failure) = try Self.next(on: client) else {
                    Issue.record("A refused resize did not report a failure.")
                    return
                }
                #expect(failure.message.contains("could not change size"))
                let reader = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { reader.shutdown() }
                try reader.greetSessionProcess()
                try reader.send(ClientMessage.listSessions)
                guard case .sessionList(let sessions) = try Self.next(on: reader) else {
                    Issue.record("The session list did not arrive.")
                    return
                }
                #expect(sessions.first(where: { $0.identifier == identifier })?.size == initial)
            }
        }

        @Test func queuedOutputUsesThePreviousGridUntilTheConfirmation() async throws {
            try await RunningSessionProcess.run { process in
                let program = ["/bin/sh", "-c", "/bin/stty -echo; printf 'ready\\n'; read line; printf '\\033[1;70HX'; /bin/sleep 60"]
                let text = try process.createSession(program: program)
                try #require(await process.waitForScreen(of: text, containing: "ready"))
                let identifier = try #require(UUID(uuidString: text))
                let initial = SessionSize(columns: 80, rows: 24)
                let requested = SessionSize(columns: 12, rows: 24)
                let (client, snapshot) = try Self.attach(to: process, identifier: identifier, size: initial)
                let (observer, _) = try Self.attach(to: process, identifier: identifier, size: initial)
                defer { client.shutdown(); observer.shutdown() }
                try observer.send(ClientMessage.input(Data("one\n".utf8)))
                var observed = ""
                while !observed.contains("X") {
                    if case .output(let bytes) = try Self.next(on: observer) { observed += String(decoding: bytes, as: UTF8.self) }
                }
                let ordered = try TerminalSnapshot(bytes: Array(snapshot)).restoreTerminal(scrollbackLimit: 10_000)
                let optimistic = try TerminalSnapshot(bytes: Array(snapshot)).restoreTerminal(scrollbackLimit: 10_000)
                try optimistic.resize(to: TerminalSize(columns: requested.columns, rows: requested.rows))
                try client.send(ClientMessage.resize(requested, requestsConfirmation: true))
                var receivedOutput = false
                var confirmed = false
                while !confirmed {
                    switch try Self.next(on: client) {
                    case .output(let bytes):
                        receivedOutput = true
                        ordered.write(bytes)
                        optimistic.write(bytes)
                    case .sizeChanged(let size, _, _):
                        #expect(size == requested)
                        #expect(receivedOutput)
                        try ordered.resize(to: TerminalSize(columns: size.columns, rows: size.rows))
                        confirmed = true
                    default: continue
                    }
                }
                let reader = try MessageConnection.connect(to: SocketLocation(path: process.socketPath))
                defer { reader.shutdown() }
                try reader.greetSessionProcess()
                try reader.send(ClientMessage.readScreen(identifier: identifier, includeScrollback: false))
                guard case .screen(let screen) = try Self.next(on: reader) else {
                    Issue.record("The session screen did not arrive.")
                    return
                }
                let orderedText = String(decoding: try ordered.formatted(.plainText), as: UTF8.self)
                let optimisticText = String(decoding: try optimistic.formatted(.plainText), as: UTF8.self)
                #expect(orderedText == screen)
                #expect(optimisticText != screen)
            }
        }
    }
}
