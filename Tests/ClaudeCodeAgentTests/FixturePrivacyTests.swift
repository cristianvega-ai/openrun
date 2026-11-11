import CryptoKit
import Foundation
import Testing

/// The repository is public, and the fixtures and some test values come
/// from runs on the owner's Mac. This test fails when a file of the agent
/// thread modules, their tests or the fake agent describes the owner. It
/// depends on nothing of the Mac that runs it.
@Suite struct FixturePrivacyTests {
    static let packageFolder = URL(fileURLWithPath: "../..", relativeTo: URL(fileURLWithPath: #filePath)).standardizedFileURL
    static let scannedFolders = [
        "Sources/AgentConversation", "Sources/ClaudeCodeAgent", "Sources/AgentProgram", "Tests/AgentConversationTests",
        "Tests/ClaudeCodeAgentTests", "Tests/AgentProgramTests", "Tests/AgentProgramProbe", "Tests/FakeAgent", "Tests/FakeAgentTests",
    ]

    /// The first 16 hexadecimal digits of the SHA-256 of each word that
    /// was removed from the recordings, in lower case: names of the owner,
    /// of the owner's folders, tools and plan, and of the recording folder.
    /// Hashes, so that this file does not name them either.
    static let removedWordHashes: Set<String> = [
        "1a5d2f594e9073e1", "1505e1f8fa878cdc", "313ce7d71787960e", "072a626ed2d6cc7d", "282a6dc5066d4725", "8c3908175a49e353",
        "7827e8eb2cb3b95f", "7f2fe580edb35154", "edb4ce8ba5473ec9", "9dde9cf87d682b7b", "4e8c59ec19506cb5", "425ed264c86619b9",
    ]

    /// Long values that were checked and describe nothing: the red square of
    /// 16 by 16 pixels in `image-turn.jsonl`, and the characters of a model
    /// name in `ClaudeCodeLaunch`. Hashes, as above.
    static let checkedLongValueHashes: Set<String> = ["7f6735613c77232c", "3717c240875cb81b"]

    static func hash(_ word: String) -> String {
        SHA256.hash(data: Data(word.lowercased().utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Each scanned file, by its path in the package, with its text.
    static func scannedFiles() throws -> [(path: String, text: String)] {
        try scannedFolders.flatMap { folder in
            let root = packageFolder.appending(path: folder)
            let urls = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])?
                .compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true } ?? []
            return try urls.map { url in
                let path = url.path.range(of: "/" + folder + "/").map { String(url.path[$0.lowerBound...].dropFirst()) } ?? url.path
                return (path, try String(contentsOf: url, encoding: .utf8))
            }
        }
    }

    /// The problems that `text` has. Each names its rule, and none repeats
    /// the value that it found.
    static func problems(in text: String) throws -> [String] {
        var problems: [String] = []
        let words = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        if words.contains(where: { removedWordHashes.contains(hash($0)) }) { problems.append("a removed word") }
        let rules: [(name: String, pattern: String, allowed: (Substring) -> Bool)] = [
            ("a real universal identifier", "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
             { $0.hasPrefix("00000000-0000-") }),
            ("a real message, request or tool identifier", "(toolu|msg|req)_(?=[A-Za-z0-9]*[0-9])[A-Za-z0-9]{6,}",
             { $0.wholeMatch(of: /(toolu|msg|req)_01Fixture[0-9]+/) != nil }),
            ("a long hexadecimal value", "[0-9A-Fa-f]{20,}", { $0.allSatisfy { $0 == "0" } }),
            ("a long base64 value", "[A-Za-z0-9+/]{40,}={0,2}", { value in
                !value.contains(where: \.isNumber) || value.allSatisfy { $0 == "0" } || checkedLongValueHashes.contains(hash(String(value))) }),
            ("a home folder", "/Users/[A-Za-z0-9._-]+", { $0 == "/Users/example" }),
            ("an e-mail address", "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", { $0.hasSuffix("@example.com") }),
        ]
        for rule in rules {
            let matches = text.matches(of: try Regex(rule.pattern))
            if matches.contains(where: { !rule.allowed(text[$0.range]) }) { problems.append(rule.name) }
        }
        return problems
    }

    @Test func noFileDescribesTheOwner() throws {
        let files = try Self.scannedFiles()
        #expect(files.count > 50)
        #expect(files.contains { $0.path.hasSuffix("Fixtures/history.jsonl") })
        for file in files {
            let problems = try Self.problems(in: file.text)
            #expect(problems.isEmpty, "\(file.path) holds \(problems)")
        }
    }

    @Test func eachRuleFindsWhatItIsFor() throws {
        let real = "4f1c" + "9a2e-1b3d-4c5e-8f60-718293a4b5c6"
        #expect(try Self.problems(in: "--resume \(real)") == ["a real universal identifier"])
        #expect(try Self.problems(in: "toolu_" + "01AbCdEf2345") == ["a real message, request or tool identifier"])
        #expect(try Self.problems(in: "msg_lifecycle toolu_01 toolu_01Fixture0001 00000000-0000-4000-8000-000000000001").isEmpty)
        #expect(try Self.problems(in: "hash " + String(repeating: "3f", count: 12)) == ["a long hexadecimal value"])
        #expect(try Self.problems(in: String(repeating: "Ab3/", count: 12)) == ["a long base64 value"])
        #expect(try Self.problems(in: "/Users/" + "someone/x /Users/example/x") == ["a home folder"])
        #expect(try Self.problems(in: "a@" + "mail.org b@example.com") == ["an e-mail address"])
    }

    @Test func theHashOfAWordIsItsDigestInLowerCase() {
        #expect(Self.hash("Example") == "50d858e0985ecc7f")
    }
}
