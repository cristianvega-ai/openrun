/// What the renderer did to get ready for one frame.
public struct FrameStatistics: Equatable, Sendable {
    /// The rows that the renderer read from the screen again.
    public var rowsPrepared = 0
    /// The rows that kept their quads from an earlier frame.
    public var rowsReused = 0
}
