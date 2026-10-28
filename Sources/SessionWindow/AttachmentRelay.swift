import Dispatch
import SessionConnection

/// Hands the events of an attachment to the main thread, in their order.
///
/// The receiving thread of `SessionAttachment` calls the handler, and the view
/// and the window live on the main thread. The main queue runs the blocks of
/// one thread in the order of their `async` calls, so output stays in order.
/// The handler returns at once, so the socket never waits for drawing.
enum AttachmentRelay {
    static func handler(_ deliver: @escaping @MainActor @Sendable (SessionAttachmentEvent) -> Void) -> @Sendable (SessionAttachmentEvent) -> Void {
        { event in
            DispatchQueue.main.async { MainActor.assumeIsolated { deliver(event) } }
        }
    }
}
