import Darwin
import Foundation
import Synchronization
import Testing
@testable import SessionProtocol

@Suite struct MessageConnectionTests {
    @Test func messagesTravelInBothDirections() throws {
        let (client, server) = try MessageConnection.makePair()
        try client.send(ClientMessage.listSessions)
        #expect(try server.receive(ClientMessage.self) == .listSessions)
        try server.send(ServerMessage.acknowledged)
        #expect(try client.receive(ServerMessage.self) == .acknowledged)
    }

    @Test func framesKeepTheirOrder() throws {
        let (client, server) = try MessageConnection.makePair()
        for number in 0..<50 {
            try client.send(ClientMessage.input(Data([UInt8(number)])))
        }
        for number in 0..<50 {
            #expect(try server.receive(ClientMessage.self) == .input(Data([UInt8(number)])))
        }
    }

    @Test func aLargePayloadArrivesWhole() throws {
        let (client, server) = try MessageConnection.makePair()
        let payload = Data((0..<2_000_000).map { UInt8(truncatingIfNeeded: $0) })
        // The socket buffer is smaller, so sending needs a reader at the same time.
        let sender = Thread { try? client.send(ServerMessage.snapshot(payload)) }
        sender.start()
        #expect(try server.receive(ServerMessage.self) == .snapshot(payload))
    }

    @Test func aCleanCloseBetweenFramesGivesNil() throws {
        let (client, server) = try MessageConnection.makePair()
        client.shutdown()
        #expect(try server.receive(ClientMessage.self) == nil)
    }

    @Test func aCloseInTheMiddleOfAFrameThrows() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        let receiver = MessageConnection(descriptor: descriptors[1])
        // A length field that promises 10 bytes, and only 2 follow.
        let partial: [UInt8] = [0, 0, 0, 10, 2, 7]
        #expect(write(descriptors[0], partial, partial.count) == partial.count)
        close(descriptors[0])
        #expect(throws: SessionProtocolError.connectionClosed) { try receiver.receive(ServerMessage.self) }
    }

    @Test func anOversizedLengthIsRejectedWithoutReadingTheBody() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        let receiver = MessageConnection(descriptor: descriptors[1])
        defer { close(descriptors[0]) }
        let huge: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        #expect(write(descriptors[0], huge, huge.count) == huge.count)
        #expect(throws: SessionProtocolError.self) { try receiver.receive(ClientMessage.self) }
    }

    @Test func writingToAClosedPeerThrowsInsteadOfEndingTheProcess() throws {
        // Dropping the other end closes its descriptor.
        let (client, _) = try MessageConnection.makePair()
        #expect(throws: SessionProtocolError.self) {
            for _ in 0..<10 { try client.send(ClientMessage.listSessions) }
        }
    }

    @Test func aFrameThatStallsEndsTheReceiveAfterTheStallLimit() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { close(descriptors[0]) }
        let receiver = MessageConnection(descriptor: descriptors[1])
        // A length field that promises 64 MiB, and ten bytes of it.
        let partial: [UInt8] = [0x04, 0x00, 0x00, 0x01, 3] + [UInt8](repeating: 0x61, count: 10)
        #expect(write(descriptors[0], partial, partial.count) == partial.count)
        let start = ContinuousClock.now
        #expect(throws: SessionProtocolError.timedOut(waitingFor: "the rest of a frame")) {
            try receiver.receive(ClientMessage.self, timeLimit: .stall(.milliseconds(200)))
        }
        #expect(ContinuousClock.now - start >= .milliseconds(200))
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func aStallLimitDoesNotEndTheWaitBetweenFrames() throws {
        let (client, server) = try MessageConnection.makePair()
        let sender = Thread {
            Thread.sleep(forTimeInterval: 0.4)
            try? client.send(ClientMessage.listSessions)
        }
        sender.start()
        #expect(try server.receive(ClientMessage.self, timeLimit: .stall(.milliseconds(100))) == .listSessions)
    }

    @Test func aControlFrameThatCannotBeParsedIsDescribedWithoutItsBytes() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { close(descriptors[0]) }
        let receiver = MessageConnection(descriptor: descriptors[1])
        let payload = Array("\u{1B}]52;c;payload-secret\u{07}".utf8)
        let frame: [UInt8] = [0, 0, 0, UInt8(payload.count + 1), 1] + payload
        #expect(write(descriptors[0], frame, frame.count) == frame.count)
        do {
            _ = try receiver.receive(ServerMessage.self)
            Issue.record("Bytes that are not JSON were decoded.")
        } catch {
            #expect(!"\(error)".contains("\u{1B}"), "error: \(error)")
            #expect(!"\(error)".contains("payload-secret"), "error: \(error)")
        }
    }

    /// The session process closes a client's descriptor
    /// itself, to know when the socket is gone. The connection must not
    /// close the number again when it goes away: by then the system may
    /// have given it to another file.
    @Test func closeEndsTheDescriptorOnceAndLaterCallsFail() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { close(descriptors[0]) }
        var connection: MessageConnection? = MessageConnection(descriptor: descriptors[1])
        connection?.close()
        #expect(fcntl(descriptors[1], F_GETFD) == -1 && errno == EBADF, "the descriptor is still open")
        #expect(throws: SessionProtocolError.self) { try connection?.send(ClientMessage.listSessions) }
        #expect(try connection?.receive(ClientMessage.self) == nil)
        connection?.close()

        // The next file gets the number that was freed.
        var pipeDescriptors: [Int32] = [0, 0]
        #expect(pipe(&pipeDescriptors) == 0)
        defer { close(pipeDescriptors[0]); close(pipeDescriptors[1]) }
        let reused = pipeDescriptors.contains(descriptors[1])
        connection = nil
        #expect(pipeDescriptors.allSatisfy { fcntl($0, F_GETFD) != -1 }, "the connection closed a descriptor it no longer owned (reused: \(reused))")
    }

    /// macOS reports a peer that shut down only its sending side while
    /// bytes still wait, so a
    /// client that half-closes counts as gone, as a client that closes
    /// between two frames does. Its other direction still works.
    @Test func aPeerThatHalfClosedIsNoticedWhileItsBytesWait() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { close(descriptors[0]) }
        let server = MessageConnection(descriptor: descriptors[1])
        let waiting = [UInt8](repeating: 7, count: 4096)
        #expect(write(descriptors[0], waiting, waiting.count) == waiting.count)
        #expect(!server.peerHasClosed)
        #expect(shutdown(descriptors[0], SHUT_WR) == 0)
        #expect(server.peerHasClosed)
        try server.send(ServerMessage.acknowledged)
    }

    @Test func aWriteThatMakesNoProgressEndsAfterTheStallLimit() throws {
        let (client, server) = try MessageConnection.makePair()
        _ = server
        // Nobody reads, so the socket fills up and the write stalls.
        let start = ContinuousClock.now
        #expect(throws: SessionProtocolError.timedOut(waitingFor: "the other side to take a frame")) {
            try client.send(ServerMessage.output(Data(count: 1024 * 1024)), stallLimit: .milliseconds(200))
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func aPeerThatClosedIsNoticedWhileItsBytesWait() throws {
        let (client, server) = try MessageConnection.makePair()
        #expect(!server.peerHasClosed)
        try client.send(ClientMessage.input(Data(count: 4096)))
        #expect(!server.peerHasClosed)
        client.shutdown()
        #expect(server.peerHasClosed)
    }
}
