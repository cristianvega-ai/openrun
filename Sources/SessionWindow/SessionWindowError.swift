/// The session process must keep output and size confirmations in order.
enum SessionWindowError: Error, Equatable, CustomStringConvertible {
    case orderedResizeUnsupported

    var description: String {
        "This session process does not support ordered size changes. Start a session process from the same build of OpenRun."
    }
}
