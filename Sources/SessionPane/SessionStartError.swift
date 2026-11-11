/// Why a pane cannot attach to its session. The session process must
/// keep output and size confirmations in order.
public enum SessionStartError: Error, Equatable, CustomStringConvertible {
    case orderedResizeUnsupported

    public var description: String {
        "This session process does not support ordered size changes. Start a session process from the same build of OpenRun."
    }
}
