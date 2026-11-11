/// A message about the conversation that is not part of an answer, such
/// as a warning or a retry of a request.
public struct Notice: Codable, Sendable, Hashable {
    public enum Level: String, Codable, Sendable {
        case information, warning, error
    }

    public var level: Level
    public var text: String

    public init(level: Level, text: String) {
        self.level = level
        self.text = text
    }
}
