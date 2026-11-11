import Foundation
import SessionConnection
import SessionProtocol

/// What a pane uses of an attached session. `SessionAttachment` is one,
/// and tests give a stand-in, so they need no socket.
protocol AttachedSession: AnyObject, Sendable {
    var snapshot: Data { get }
    func send(input: Data) throws
    func send(size: SessionSize) throws
    func send(size: SessionSize, requestsConfirmation: Bool) throws
    func detach() throws
    func shutdown()
    func startReceiving(_ handler: @escaping @Sendable (SessionAttachmentEvent) -> Void)
}

extension SessionAttachment: AttachedSession {}
