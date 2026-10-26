/// How much of the picture changed since it was last marked clean.
public enum RenderDirtiness: Equatable, Sendable {
    case nothing
    case someRows
    case everything
}
