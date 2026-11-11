import Foundation

/// A change of the threads was refused. Nothing changed.
public enum ThreadListError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownThread(UUID)
    case duplicateThread(UUID)
    /// The name is too long or holds a control character.
    case invalidName
    /// The folder is not an absolute path, or it is too long.
    case invalidFolder
    /// The model or the permission mode is empty, too long, or holds a
    /// character that no such word has.
    case invalidModel
    case invalidPermissionMode
    case tooManyThreads(limit: Int)

    public var description: String {
        switch self {
        case .unknownThread(let identifier): "No thread has the identifier \(identifier.uuidString.lowercased())."
        case .duplicateThread(let identifier): "A thread already has the identifier \(identifier.uuidString.lowercased())."
        case .invalidName: "A thread name has at most \(ThreadList.nameLengthLimit) characters and no control characters."
        case .invalidFolder: "The folder of a thread is an absolute path."
        case .invalidModel: "The model of a thread is a short word of letters, digits and marks, such as opus."
        case .invalidPermissionMode: "The permission mode of a thread is a short word of letters, such as default."
        case .tooManyThreads(let limit): "OpenRun keeps at most \(limit) threads. Close a thread first."
        }
    }
}
