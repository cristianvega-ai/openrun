/// The identity of a row across updates of a `RenderState`. Identifiers are
/// never reused.
public struct RowIdentifier: Hashable, Sendable {
    let first: UInt64
    let second: UInt64
}
