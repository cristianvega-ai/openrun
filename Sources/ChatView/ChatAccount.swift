/// An account of the user for an agent, such as "Work" or "Personal".
public struct ChatAccount: Equatable, Hashable, Sendable {
    public var identifier: String
    public var name: String

    public init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }
}
