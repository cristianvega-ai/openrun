/// The result of one run of the `openrun` command.
public struct CommandResult: Sendable {
    public let status: Int32
    public let standardOutput: String
    public let standardError: String

    /// The lines of standard output.
    public var outputLines: [String] {
        standardOutput.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
