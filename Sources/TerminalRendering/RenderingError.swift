/// A step of the renderer did not work.
public enum RenderingError: Error, Equatable, Sendable {
    /// Metal gave no texture, for example because the device has no memory left.
    case textureUnavailable
    /// Metal could not compile the shaders. The text is the message of Metal.
    case shaderCompilationFailed(String)
}
