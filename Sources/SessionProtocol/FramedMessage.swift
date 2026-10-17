/// A message that knows its frame.
public protocol FramedMessage: Sendable {
    func frame() throws -> MessageFrame
    init(frame: MessageFrame) throws
}
