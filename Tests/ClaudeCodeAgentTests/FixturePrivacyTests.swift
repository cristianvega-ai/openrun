import CryptoKit
import Foundation
import Testing

/// The repository is public, and the fixtures come from runs on the
/// owner's Mac. This test fails when a fixture describes the owner.
@Suite struct FixturePrivacyTests {
    static let folder = URL(fileURLWithPath: "Fixtures", relativeTo: URL(fileURLWithPath: #filePath)).standardizedFileURL

    /// The first 16 hexadecimal digits of the SHA-256 of each word that
    /// was removed from the recordings, in lower case: names of the owner,
    /// of the owner's folders, tools and plan, and of the recording folder.
    /// Hashes, so that this file does not name them either.
    static let removedWordHashes: Set<String> = [
        "1a5d2f594e9073e1", "1505e1f8fa878cdc", "313ce7d71787960e", "072a626ed2d6cc7d", "282a6dc5066d4725", "8c3908175a49e353",
        "7827e8eb2cb3b95f", "7f2fe580edb35154", "edb4ce8ba5473ec9", "9dde9cf87d682b7b", "4e8c59ec19506cb5", "425ed264c86619b9",
    ]

    static func hash(_ word: String) -> String {
        SHA256.hash(data: Data(word.lowercased().utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    @Test func noFixtureDescribesTheOwner() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)
        #expect(files.count >= 3)
        let address = try Regex("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
        let personal = [NSHomeDirectory(), NSUserName(), NSFullUserName(), "/Users/", "Users-USER", "scratchpad"]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let name = file.lastPathComponent
            for word in personal where !word.isEmpty {
                #expect(!text.localizedCaseInsensitiveContains(word), "\(name) holds a personal word")
            }
            #expect(text.firstMatch(of: address) == nil, "\(name) holds an e-mail address")
            let words = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
            let found = words.filter { Self.removedWordHashes.contains(Self.hash($0)) }
            #expect(found.isEmpty, "\(name) holds \(found.count) removed words")
        }
    }

    /// Real identifiers can lead to the owner's account, so each one in a
    /// fixture is a made-up one, also where it is the key of an object.
    @Test func everyIdentifierIsAMadeUpOne() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)
        let opaque = try Regex("(toolu|msg|req)_[A-Za-z0-9]{10,}")
        let universal = try Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
        let hash = try Regex("[0-9a-fA-F]{20,}")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: opaque) {
                #expect(text[match.range].contains("Fixture"), "\(file.lastPathComponent) holds a real identifier")
            }
            for match in text.matches(of: universal) {
                #expect(text[match.range].hasPrefix("00000000-0000-"), "\(file.lastPathComponent) holds a real identifier")
            }
            // A hash, such as the hash of the system prompt, is only zeros.
            for match in text.matches(of: hash) {
                #expect(text[match.range].allSatisfy { $0 == "0" }, "\(file.lastPathComponent) holds a real hash")
            }
        }
    }

    @Test func theHashOfAWordIsItsDigestInLowerCase() {
        #expect(Self.hash("Example") == "50d858e0985ecc7f")
    }
}
