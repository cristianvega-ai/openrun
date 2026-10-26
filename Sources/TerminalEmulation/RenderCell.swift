/// One cell of a row.
public struct RenderCell: Sendable {
    public var column: UInt16
    /// The first scalar of the cluster, or `nil` for an empty cell.
    public var base: Unicode.Scalar?
    /// The rest of the cluster, such as a combining mark.
    public var extraScalars: [Unicode.Scalar]
    public var width: CellWidth

    /// The whole cluster as text.
    public var text: String {
        base.map { String(String.UnicodeScalarView([$0] + extraScalars)) } ?? ""
    }
}
