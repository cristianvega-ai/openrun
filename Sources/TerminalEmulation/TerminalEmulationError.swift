import GhosttyVt

/// A libghostty-vt call did not succeed.
public struct TerminalEmulationError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The libghostty-vt function that failed, such as `ghostty_terminal_new`.
    public let function: String
    /// The `GhosttyResult` value that the function returned.
    public let resultCode: Int32

    public init(function: String, resultCode: Int32) {
        self.function = function
        self.resultCode = resultCode
    }

    public var description: String {
        "\(function) failed with result code \(resultCode)"
    }
}

extension TerminalEmulationError {
    /// Throws when `result` is not `GHOSTTY_SUCCESS`.
    static func check(_ result: GhosttyResult, from function: String) throws {
        guard result == GHOSTTY_SUCCESS else {
            throw TerminalEmulationError(function: function, resultCode: result.rawValue)
        }
    }

    /// The error for a value that this module refuses before it calls
    /// libghostty-vt, such as a negative scrollback limit. `function` names
    /// the OpenRun function that refused it.
    static func invalidValue(in function: String) -> TerminalEmulationError {
        TerminalEmulationError(function: function, resultCode: GHOSTTY_INVALID_VALUE.rawValue)
    }
}
