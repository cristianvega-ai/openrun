import Darwin
import Foundation

/// The app bundle that holds the program of this process, such as
/// `OpenRun.app` for `OpenRun.app/Contents/MacOS/openrun-session`.
enum ApplicationBundle {
    /// The path of the program of this process. The process reads it at
    /// its start, because a new build can replace the bundle while the
    /// process runs.
    static func executablePathOfThisProcess() -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(getpid(), &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// `NAME.app/Contents/MacOS/PROGRAM` gives `NAME.app`. A program
    /// outside that layout, such as one of `swift build`, gives nil.
    static func path(holdingExecutableAt path: String) -> String? {
        let components = (path as NSString).pathComponents
        guard components.count >= 4,
              components[components.count - 2] == "MacOS",
              components[components.count - 3] == "Contents",
              components[components.count - 4].hasSuffix(".app") else { return nil }
        return NSString.path(withComponents: Array(components.dropLast(3)))
    }
}
