import Foundation
import SessionConnection
import SessionLaunch
import SessionProtocol

/// Keeps a `SessionOverview` in step with the session process.
///
/// A thread of its own receives the feed, so the main thread never waits
/// for the socket. The changes reach the main thread in batches, in order.
/// When the connection ends, the last facts stay.
@MainActor
public final class SessionOverviewConnection {
    public private(set) var overview = SessionOverview()
    public private(set) var status = ConnectionStatus.connecting
    /// Called after each batch that changed the overview, with the
    /// overview before the batch.
    public var overviewChanged: ((_ previous: SessionOverview) -> Void)?
    public var statusChanged: (() -> Void)?
    /// Opens the feed. Tests give their own.
    var open: @Sendable (SocketLocation) throws -> SessionChangeReceiver = SessionOverviewConnection.openFeed
    private let socket: SocketLocation
    private var receiver: SessionChangeReceiver?
    /// The number of the present connection or try. An event of an older
    /// connection must not change the overview.
    private var generation = 0
    private var isStarted = false

    public init(socket: SocketLocation) {
        self.socket = socket
    }

    /// Connects. Later calls do nothing.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        connect()
    }

    nonisolated static func openFeed(at socket: SocketLocation) throws -> SessionChangeReceiver {
        let client = try SessionClient(location: socket, helloTimeLimit: SessionWake.answerTimeLimit)
        guard client.capabilities.sessionChanges, client.capabilities.projectsAndSettings else { throw OlderSessionProcess() }
        return try client.receiveSessionChanges()
    }

    private func connect() {
        generation += 1
        let (socket, open, generation) = (socket, open, generation)
        Thread.detachNewThread { [weak self] in
            let result = Result { try open(socket) }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.connected(result, generation: generation) } }
        }
    }

    private func connected(_ result: Result<SessionChangeReceiver, any Error>, generation: Int) {
        guard generation == self.generation else {
            if case .success(let receiver) = result { receiver.shutdown() }
            return
        }
        switch result {
        case .success(let receiver):
            self.receiver = receiver
            setStatus(.connected)
            let pending = PendingChanges()
            receiver.startReceiving { [weak self] event in
                guard pending.add(event) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.take(pending, generation: generation) } }
            }
        case .failure(let error):
            lostConnection(reason: "\(error)")
        }
    }

    private func take(_ pending: PendingChanges, generation: Int) {
        guard generation == self.generation else { return }
        let previous = overview
        var end: String?
        for event in pending.takeAll() {
            overview.apply(event)
            switch event {
            case .closed: end = "\(SessionConnectionError.connectionClosed)"
            case .failed(let error): end = "\(error)"
            default: break
            }
        }
        if overview != previous { overviewChanged?(previous) }
        if let end { lostConnection(reason: end) }
    }

    private func lostConnection(reason: String) {
        receiver = nil
        setStatus(.disconnected(reason: reason))
    }

    private func setStatus(_ new: ConnectionStatus) {
        guard new != status else { return }
        status = new
        statusChanged?()
    }
}
