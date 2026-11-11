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
        var lastLine = ""
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
                    lastLine = encode(line)
                    write(lastLine)
                } else if let status = special(step["special"] as? String ?? "", lastLine: lastLine) {
                    return status
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

    /// Plays a special case, and returns the exit status when it ends the
    /// program.
    func special(_ name: String, lastLine: String) -> Int32? {
        switch name {
        case "hang":
            // No answer comes. The program ends with its input.
            while readLine() != nil {}
            return 0
        case "deaf":
            // No answer comes, and neither the end of the input nor SIGTERM
            // ends the program. Only SIGKILL does.
            signal(SIGTERM, SIG_IGN)
            while true { sleep(60) }
        case "exit":
            // The app-server waits for an answer. It must not get one: it
            // ends with the input, as Codex does, and runs nothing.
            while let line = readLine() { return fail("a line came while the approval waited: \(line.prefix(60))", status: 3) }
            return 0
        case "cutLine":
            write(String(decoding: lastLine.utf8.prefix(lastLine.utf8.count / 2), as: UTF8.self), lineEnd: false)
            return 1
        case "crash":
            kill(getpid(), SIGKILL)
            return 1
        default:
            return fail("unknown special case \(name)")
        }
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
