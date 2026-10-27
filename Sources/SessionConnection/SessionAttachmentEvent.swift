import Foundation
import SessionProtocol

/// What the session process tells an attached client after the snapshot.
/// `exited`, `closed` and `failed` come last.
public enum SessionAttachmentEvent: Equatable, Sendable {
    /// Bytes that the program wrote, as the protocol carries them.
    case output(Data)
    /// Another client changed the size of the session. Only an attachment
    /// that asked for size changes gets this. The output after it is for the
    /// new size.
    case sizeChanged(SessionSize)
    /// The program ended.
    case exited(SessionExit)
    /// The connection closed before the program ended: the session process
    /// closed it, or this client shut it down.
    case closed
    /// Receiving failed, such as on a frame that cannot be read.
    case failed(SessionConnectionError)
}
