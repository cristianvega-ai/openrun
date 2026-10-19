import Darwin
import Foundation

/// A real `openrun-session` process on a socket in a private folder, for
/// integration tests. The folder lives under `TMPDIR`, because a Unix socket
/// path must stay short.
public final class RunningSessionProcess: @unchecked Sendable {
    /// Where the products of the build are: the folder that holds the test
    /// bundle also holds the executables that the tests depend on.
    public static let productsDirectory: URL = {
        for bundle in Bundle.allBundles where bundle.bundleURL.pathExtension == "xctest" {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        // swift test runs the bundle from a helper process in some versions.
        for argument in CommandLine.arguments where argument.contains(".xctest") {
            if let range = argument.range(of: ".xctest") {
                return URL(fileURLWithPath: String(argument[..<range.upperBound])).deletingLastPathComponent()
            }
        }
        return Bundle.main.bundleURL.deletingLastPathComponent()
    }()

    public static var sessionExecutable: URL { productsDirectory.appendingPathComponent("openrun-session") }
    public static var commandExecutable: URL { productsDirectory.appendingPathComponent("openrun") }

    /// A new private folder with a short name under `TMPDIR`. The system
    /// makes the name and refuses one that exists, so two calls never share a
    /// folder, also when an earlier run left one behind.
    public static func makeDirectory() throws -> URL {
        let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
        var template = Array((base as NSString).appendingPathComponent("test-" + String(repeating: "X", count: 6)).utf8CString)
        guard mkdtemp(&template) != nil else {
            throw HarnessError.commandFailed(description: "A folder under \(base) cannot be made: \(String(cString: strerror(errno)))")
        }
        let path = String(decoding: template.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// Polls until the condition holds or the timeout passes.
public func eventually(timeout: Duration = .seconds(15), _ condition: () async throws -> Bool) async rethrows -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if try await condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return try await condition()
}
