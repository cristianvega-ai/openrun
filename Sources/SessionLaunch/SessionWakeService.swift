import XPC

/// The session process side of the start on demand. It takes the Mach
/// service that launchd holds for the launch agent, and answers each wake
/// request with the socket path.
///
/// Create it only after the socket listens, because a client that gets the
/// answer connects at once. A request that arrives earlier waits in the
/// Mach port, so no wake is lost. Only programs of the same user can look
/// up a service in the launchd domain of the user, and the answer holds
/// only a path that each client computes anyway, so the service checks no
/// peer.
public final class SessionWakeService: Sendable {
    private let listener: XPCListener

    /// - Throws: An error when launchd did not start this process for the
    ///   service, such as a session process that was started by hand.
    public init(socketPath: String, machServiceName: String) throws {
        listener = try XPCListener(service: machServiceName, incomingSessionHandler: Self.handler(socketPath: socketPath))
    }

    /// An anonymous listener lets a test use the same request handler.
    init(socketPath: String) {
        listener = XPCListener(incomingSessionHandler: Self.handler(socketPath: socketPath))
    }

    var endpoint: XPCEndpoint { listener.endpoint }

    private static func handler(socketPath: String) -> @Sendable (XPCListener.IncomingSessionRequest) -> XPCListener.IncomingSessionRequest.Decision {
        { request in
            request.accept { (_: WakeRequest) -> (any Encodable)? in
                WakeAnswer(socketPath: socketPath)
            }
        }
    }

    /// Stops the answers. A request that comes later waits in the Mach
    /// port, and launchd starts the program again for it after this
    /// process ends.
    public func cancel() {
        listener.cancel()
    }
}
