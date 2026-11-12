import Foundation
import SessionConnection
import SessionLaunch
import SessionProtocol

/// Keeps a `SessionOverview` in step with the session process.
///
/// A thread of its own receives the feed, so the main thread never waits
/// for the socket. The changes reach the main thread in batches, in order.
/// When the connection ends, the last facts stay, and the next try comes
/// after a wait that grows. On the default socket a try also wakes the
/// launch agent, so the session process runs while the app runs.
@MainActor
public final class SessionOverviewConnection {
    public private(set) var overview = SessionOverview()
    public private(set) var status = ConnectionStatus.connecting
    /// Whether a list of the sessions came since the start. Before it, the
    /// overview holds no session, and that does not mean that none runs.
    public private(set) var hasSessionList = false
    /// Whether a list of the agent threads came since the start. A
    /// session process of an older build sends none.
    public private(set) var hasThreadList = false
    /// The identifier of the build of the session process of the present
    /// connection. An older session process tells none.
    public private(set) var sessionProcessBuild: String?
    /// Whether every list of the start came: the sessions, and the threads
    /// from a session process that keeps threads. Only then does an empty
    /// overview mean that nothing runs.
    public var hasFirstLists: Bool { hasSessionList && (hasThreadList || !expectsThreadList) }
    private var expectsThreadList = true
    /// Called after each batch that changed the overview or made the
    /// first lists complete, with the overview before the batch.
    public var overviewChanged: ((_ previous: SessionOverview) -> Void)?
    public var statusChanged: (() -> Void)?
    /// Opens the feed. Tests give their own.
    var open: @Sendable (SocketLocation) throws -> SessionChangeReceiver = SessionOverviewConnection.openFeed
    /// The wait before the second try. Each later wait is twice as long,
    /// up to `longestRetryDelay`.
    var firstRetryDelay = Duration.milliseconds(500)
    static let longestRetryDelay = Duration.seconds(10)
    private lazy var retryDelay = firstRetryDelay
    private let socket: SocketLocation
    private var receiver: SessionChangeReceiver?
    /// The number of the present connection or try. An event of an older
    /// connection must not change the overview.
    private var generation = 0
    private var isStarted = false

    public init(socket: SocketLocation) {
        self.socket = socket
    }

    /// Connects, and connects again after each end. Later calls do nothing.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        connect()
    }

    /// Ends the connection for good, such as when the app quits.
    public func stop() {
        generation += 1
        receiver?.shutdown()
        receiver = nil
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
            (expectsThreadList, sessionProcessBuild) = (receiver.includesThreads, receiver.build)
            retryDelay = firstRetryDelay
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
        let (previous, hadFirstLists) = (overview, hasFirstLists)
        var end: String?
        for event in pending.takeAll() {
            overview.apply(event)
            switch event {
            case .sessions: hasSessionList = true
            case .threads: hasThreadList = true
            case .closed: end = "\(SessionConnectionError.connectionClosed)"
            case .failed(let error): end = "\(error)"
            default: break
            }
        }
        if overview != previous || hasFirstLists != hadFirstLists { overviewChanged?(previous) }
        if let end { lostConnection(reason: end) }
    }

    private func lostConnection(reason: String) {
        receiver = nil
        setStatus(.disconnected(reason: reason))
        let (delay, generation) = (retryDelay, generation)
        retryDelay = min(retryDelay * 2, Self.longestRetryDelay)
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, generation == self.generation else { return }
            self.connect()
        }
    }

    private func setStatus(_ new: ConnectionStatus) {
        guard new != status else { return }
        status = new
        statusChanged?()
    }
}
