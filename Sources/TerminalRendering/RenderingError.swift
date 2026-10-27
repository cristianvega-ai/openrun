/// A step of the renderer did not work.
public enum RenderingError: Error, Equatable, Sendable {
    /// Metal gave no texture, for example because the device has no memory left.
    case textureUnavailable
}
