import Darwin
import UntrustedText

/// The data folder or one of its files could not be used.
public enum DataStorageError: Error, Equatable, Sendable, CustomStringConvertible {
    /// What should be the data folder is a file of another kind.
    case notAFolder(path: String)
    /// The data folder did not exist and could not be made.
    case folderNotCreated(path: String)
    /// A system call failed. `code` is the `errno` value.
    case systemCallFailed(function: String, code: Int32)
    /// A document could not be turned into JSON. Nothing was written.
    case documentNotEncoded(file: String)

    /// Captures `errno` right after a failed call.
    static func failure(of function: String) -> DataStorageError {
        .systemCallFailed(function: function, code: errno)
    }

    public var description: String {
        switch self {
        case .notAFolder(let path):
            "The data folder \(QuotedText.quoted(path)) is not a folder."
        case .folderNotCreated(let path):
            "The data folder \(QuotedText.quoted(path)) could not be made."
        case .systemCallFailed(let function, let code):
            "\(function) failed: \(String(cString: strerror(code)))"
        case .documentNotEncoded(let file):
            "The document for \(file) could not be written as JSON."
        }
    }
}
