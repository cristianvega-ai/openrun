import Darwin
import Foundation

public final class RunningSessionProcess: @unchecked Sendable {

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
