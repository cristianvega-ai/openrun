import Darwin
import Foundation

/// A stand-in for `codex app-server`, so that no test runs the real agent,
/// spends the owner's subscription, or writes into the owner's Codex
/// configuration. It plays recorded exchanges in the form that
/// `Tests/CodexAgentTests/Fixtures/README.md` describes.
///
/// `FAKE_CODEX_SCRIPTS` holds the fixture files, separated by colons, which
/// play one after the other. A line of OpenRun that the step does not
/// expect ends the program with the status 2. After the last step, each
/// request gets an empty answer, and the end of the input ends the program.
struct FakeCodex {
    let environment: [String: String]

    func run(arguments: [String]) -> Int32 {
        guard arguments == ["app-server"] else { return fail("the arguments are not `app-server`", status: 64) }
        let files = (environment["FAKE_CODEX_SCRIPTS"] ?? "").split(separator: ":").map(String.init)
        var request: Any = NSNull()
        for file in files {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return fail("cannot read \(file)") }
            for stepText in text.split(separator: "\n") {
                guard let step = object(String(stepText)) else { return fail("a step is not an object") }
                if let method = step["client"] as? String {
                    guard let line = readLine(), let message = object(line) else { return fail("the input ended before \(method)") }
                    if let problem = check(message, method: method, expect: step["expect"] as? [String: Any]) { return fail(problem, status: 2) }
                    if method != "answer" { request = message["id"] ?? NSNull() }
                } else if var line = step["server"] as? [String: Any] {
                    if line["id"] as? String == "$request" { line["id"] = request }
                    write(encode(line))
                } else {
                    return fail("unknown step")
                }
            }
        }
        // After the script, each request gets an empty answer.
        while let line = readLine() {
            if let message = object(line), message["method"] != nil, let identifier = message["id"] {
                write(encode(["id": identifier, "result": [String: Any]()]))
            }
        }
        return 0
    }

    /// Checks a line of OpenRun against a step. Returns the problem.
    func check(_ message: [String: Any], method: String, expect: [String: Any]?) -> String? {
        let content = (method == "answer" ? message["result"] : message["params"]) as? [String: Any] ?? [:]
        if method == "answer" ? message["method"] != nil : message["method"] as? String != method {
            return "OpenRun sent \(message["method"] ?? "an answer") in place of \(method)"
        }
        for (key, value) in expect ?? [:] where !((content[key] as? NSObject)?.isEqual(value) ?? false) {
            return "the member \(key) of \(method) is not the expected one"
        }
        return nil
    }

    func object(_ line: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }

    func encode(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    func write(_ text: String, lineEnd: Bool = true) {
        // A reader that went away ends the program, as it ends Codex.
        do { try FileHandle.standardOutput.write(contentsOf: Data((lineEnd ? text + "\n" : text).utf8)) } catch { exit(1) }
    }

    func fail(_ problem: String, status: Int32 = 1) -> Int32 {
        try? FileHandle.standardError.write(contentsOf: Data("\(problem)\n".utf8))
        return status
    }
}
