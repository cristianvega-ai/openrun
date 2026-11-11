/// Whether the app hears the session process now. A window shows a notice
/// while there is no connection, because its lists can be out of date.
public enum ConnectionStatus: Equatable, Sendable {
    /// The first connection is on its way.
    case connecting
    case connected
    /// No connection now. The next try comes by itself.
    case disconnected(reason: String)
}
