import Dispatch
import Foundation
import SessionProtocol
import Synchronization
final class ClientConnection: Sendable {
    /// A message from the client, and the room it takes in the read-ahead.
    struct Received: Sendable {
        let message: ClientMessage
    }

    let messages: AsyncStream<Received>

    private enum Phase {
        case open
        /// Queued messages still go out. Nothing new is queued.
        case closing
        /// The socket is shut down.
        case ended
    }

    private struct State {
        var phase = Phase.open
    }

    private enum Admission {
        case queued
        case refused
    }

    private let connection: MessageConnection
    private let writeQueue = DispatchQueue(label: "ClientConnection.write")
    private let state = Mutex(State())

    init(connection: MessageConnection) {
        self.connection = connection
        let (stream, continuation) = AsyncStream.makeStream(of: Received.self)
        messages = stream
        let thread = Thread { [weak self] in
            defer {
                continuation.finish()
            }
            do {
                try connection.greetClient()
                while true {
                    let frame = try connection.receive(MessageFrame.self)
                    // The client closed the connection between two frames.
                    guard let frame else { return }
                    let message = try ClientMessage(frame: frame)
                    continuation.yield(Received(message: message))
                }
            } catch {
                self?.endIfOpen()
            }
        }
        thread.name = "ClientConnection.read"
        thread.start()
    }

    // MARK: - Private


    private func endIfOpen() {
        guard state.withLock({ $0.phase == .open }) else { return }
        end()
    }

    /// Ends the connection at once. Messages that still wait are lost. The
    /// shutdown wakes the reading thread and a write that waits.
    private func end() {
        let ends = state.withLock { state -> Bool in
            guard state.phase != .ended else { return false }
            state.phase = .ended
            return true
        }
        guard ends else { return }
        connection.shutdown()
    }
}
